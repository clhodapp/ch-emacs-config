;; SPDX-License-Identifier: MIT
;;; -*- lexical-binding: t -*-
;; init daemon
;;
;; Managed Emacs daemon lifecycle.  The systemd template unit
;; emacs-daemon@.service starts this Emacs with --fg-daemon=server;
;; home-manager activation rotates the canonical "server" socket by
;; renaming the old one to a per-instance drain socket before starting
;; the new instance.
;;
;; Taint: when a new generation is activated, this daemon receives
;; (ch-emacs-config-daemon-taint "server-drain-<pid>") via emacsclient,
;; after the activation script has already renamed the socket file.
;; After that:
;;  - the daemon adopts the drain socket name, so it stays reachable for
;;    rescue (unsaved buffers) and its exit-time socket cleanup deletes
;;    its own file, not the new daemon's canonical socket.  Adoption
;;    must cover BOTH deletion paths: lisp `server-stop' deletes by
;;    `server-name', but the C core also unlinks the bind path it
;;    recorded at daemon startup (`internal--daemon-sockname') no
;;    matter what `server-name' says — left unredirected, every
;;    rotated daemon deletes the new generation's canonical socket
;;    when it finally drains (field incident 2026-07-31)
;;  - a drain timer exits this Emacs once its last client frame is gone
;;    (see ch-emacs-config-daemon--drain-p).  Frames are the only roots:
;;    the user decides when the daemon dies by closing the last frame;
;;    anything else that kept a frameless daemon alive (unsaved buffers,
;;    terminals running a job, waiting clients) would only leak a daemon
;;    nothing can reach.  Upstream `server-stop-automatically' `empty'
;;    is unusable here because any subprocess with query-on-exit set
;;    (every ghostel shell, language servers) blocks it forever
;;  - closing its last frame shows a notice — naming any unsaved
;;    file-visiting buffers and any terminals running a job, both of
;;    which the drain exit discards — and offers Cancel

(require 'server)

(defvar ch-emacs-config-daemon--tainted nil
  "Non-nil when this daemon has been superseded by a newer generation.")

(defvar ch-emacs-config-daemon--drain-timer nil
  "Timer that exits a tainted daemon once it has drained.")

(defun ch-emacs-config-daemon--drain-p ()
  "Whether this tainted daemon has nothing left worth staying alive for.
Drained means: no client frames (the daemon's own initial frame does
not count).  Frames are the only roots.  Unsaved buffers, terminal
subprocesses running a job, and frameless server clients deliberately
do not keep the daemon alive: the user decides when it dies by closing
the last frame, and the last-frame-close prompt names what that
discards so they can cancel.  A frameless daemon kept alive by any of
those is a leak nothing can connect to."
  (not (seq-some (lambda (f) (frame-parameter f 'client))
                 (frame-list))))

(defun ch-emacs-config-daemon--drain-check ()
  "Exit a tainted daemon once `ch-emacs-config-daemon--drain-p' holds."
  (when (and ch-emacs-config-daemon--tainted
             (ch-emacs-config-daemon--drain-p))
    (kill-emacs)))

(defun ch-emacs-config-daemon-taint (&optional drain-socket-name)
  "Mark this daemon as superseded.  Called by the HM activation script.
DRAIN-SOCKET-NAME is the per-instance socket file name the activation
script renamed this daemon's socket to; adopting it keeps emacsclient
access working and points exit-time socket deletion at our own file
instead of the canonical one the new daemon now owns.  Both deleters
must be retargeted: `server-stop' (via `server-name') and the C
core's daemon shutdown (via `internal--daemon-sockname', the bind
path recorded at startup, deleted regardless of `server-name')."
  (setq ch-emacs-config-daemon--tainted t)
  (when drain-socket-name
    (setq server-name drain-socket-name)
    (when (boundp 'internal--daemon-sockname)
      (setq internal--daemon-sockname
            (expand-file-name drain-socket-name server-socket-dir))))
  (unless ch-emacs-config-daemon--drain-timer
    (setq ch-emacs-config-daemon--drain-timer
          (run-with-timer 10 2 #'ch-emacs-config-daemon--drain-check)))
  (message "Emacs updated — this daemon will close when the last frame closes"))

(defun ch-emacs-config-daemon--busy-terminal-buffers ()
  "Buffers of terminal subprocesses currently running a foreground job.
An idle shell at its prompt is not listed; a shell with a running
child is, because the drain exit kills that job."
  (delq nil
        (mapcar (lambda (p)
                  (and (memq (process-status p) '(run stop))
                       (process-tty-name p)
                       (ignore-errors (process-running-child-p p))
                       (buffer-live-p (process-buffer p))
                       (process-buffer p)))
                (process-list))))

(defun ch-emacs-config-daemon--last-frame-prompt ()
  "Confirmation prompt for closing a tainted daemon's last client frame.
Names any unsaved file-visiting buffers and any terminals running a
job: neither is a drain root, and the drain timer's `kill-emacs'
discards both without asking, so this prompt is the last chance to
cancel and save, or let the job finish."
  (let* ((unsaved (seq-filter (lambda (b)
                                (and (buffer-file-name b)
                                     (buffer-modified-p b)))
                              (buffer-list)))
         (busy (ch-emacs-config-daemon--busy-terminal-buffers))
         (losses (delq nil
                       (list (and unsaved
                                  (format "unsaved changes in %s"
                                          (mapconcat #'buffer-name unsaved ", ")))
                             (and busy
                                  (format "running jobs in %s"
                                          (mapconcat #'buffer-name busy ", ")))))))
    (if losses
        (format "This Emacs daemon is from an old generation and will \
exit, discarding %s.  Really close? "
                (string-join losses " and "))
      "This Emacs daemon is from an old generation and will exit.  \
Really close? ")))

(defun ch-emacs-config-daemon--last-frame-query ()
  "Warn before closing when this is the last frame of a tainted daemon.
Covers \\[save-buffers-kill-terminal]-style exits, which go through
`kill-emacs-query-functions'."
  (if (and ch-emacs-config-daemon--tainted
           (daemonp)
           ;; Only intervene when this is truly the last client frame.
           ;; `server-done' already closed the current frame by the time
           ;; kill-emacs-query-functions fires on daemon exit, so count
           ;; all visible + iconified frames.
           (<= (length (frame-list)) 1))
      (yes-or-no-p (ch-emacs-config-daemon--last-frame-prompt))
    t))

(defun ch-emacs-config-daemon--confirm-frame-close (orig event)
  "Ask before the window manager closes a tainted daemon's last client frame.
Frame deletion never goes through `kill-emacs', so the
`kill-emacs-query-functions' warning cannot fire on the WM close
button; this advice on `handle-delete-frame' is that path's gate.
Declining leaves the frame open; confirming closes it, after which
the drain timer exits the daemon."
  (let ((frame (posn-window (event-start event))))
    (if (and ch-emacs-config-daemon--tainted
             (daemonp)
             (framep frame)
             (frame-parameter frame 'client)
             (not (seq-some (lambda (f)
                              (and (not (eq f frame))
                                   (frame-parameter f 'client)))
                            (frame-list))))
        (when (yes-or-no-p (ch-emacs-config-daemon--last-frame-prompt))
          (funcall orig event))
      (funcall orig event))))

(when (daemonp)
  (add-hook 'kill-emacs-query-functions
            #'ch-emacs-config-daemon--last-frame-query)
  (advice-add 'handle-delete-frame :around
              #'ch-emacs-config-daemon--confirm-frame-close))
