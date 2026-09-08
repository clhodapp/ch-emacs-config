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
;;    which the drain exit discards — and offers Cancel.  The notice is
;;    an advice on `delete-frame', which every close path ends at, plus
;;    one on `server-delete-client' for blocking clients, which tear
;;    down before their frame goes (see
;;    ch-emacs-config-daemon--confirm-delete-frame and
;;    ch-emacs-config-daemon--confirm-delete-client)

(require 'server)

(defvar ch-emacs-config-daemon--tainted nil
  "Non-nil when this daemon has been superseded by a newer generation.")

(defvar ch-emacs-config-daemon--drain-timer nil
  "Timer that exits a tainted daemon once it has drained.")

(defun ch-emacs-config-daemon--client-frame-p (frame)
  "Whether FRAME is a top-level emacsclient frame.
Child frames are excluded: `frame-inherited-parameters' carries
`client', so a popup child frame (completion, tooltips) made inside a
client frame inherits the parameter, yet it dies with its parent and
is not something the user closes."
  (and (frame-parameter frame 'client)
       (not (frame-parent frame))))

(defun ch-emacs-config-daemon--last-client-frame-p (frame)
  "Whether FRAME is this daemon's only client frame."
  (and (ch-emacs-config-daemon--client-frame-p frame)
       (not (seq-some (lambda (f)
                        (and (not (eq f frame))
                             (ch-emacs-config-daemon--client-frame-p f)))
                      (frame-list)))))

(defun ch-emacs-config-daemon--drain-p ()
  "Whether this tainted daemon has nothing left worth staying alive for.
Drained means: no client frames (the daemon's own initial frame does
not count).  Frames are the only roots.  Unsaved buffers, terminal
subprocesses running a job, and frameless server clients deliberately
do not keep the daemon alive: the user decides when it dies by closing
the last frame, and the last-frame-close prompt names what that
discards so they can cancel.  A frameless daemon kept alive by any of
those is a leak nothing can connect to."
  (not (seq-some #'ch-emacs-config-daemon--client-frame-p (frame-list))))

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

(defun ch-emacs-config-daemon--confirm-delete-frame (orig &optional frame force)
  "Ask before deleting a tainted daemon's last client frame.
Every way the user closes a frame ends at `delete-frame': the window
manager's close button (`handle-delete-frame'), \\[delete-frame],
evil's :q, and \\[save-buffers-kill-terminal] / :qa on a `nowait'
frame (`server-save-buffers-kill-terminal' deletes the frame outright
while the daemon's own initial frame keeps `frame-list' longer than
one, so its `save-buffers-kill-emacs' branch is unreachable).  Gating
here covers all of them at once.  Declining leaves the frame open;
confirming deletes it, after which the drain timer exits the daemon.

A blocking client (emacsclient without -n) closed with
\\[save-buffers-kill-terminal] or :qa! reaches `delete-frame' only
from inside `server-delete-client', with the frame's `client'
parameter already cleared; that path is gated by
`ch-emacs-config-daemon--confirm-delete-client' instead."
  (let ((frame (or frame (selected-frame))))
    (if (and ch-emacs-config-daemon--tainted
             (daemonp)
             (frame-live-p frame)
             (ch-emacs-config-daemon--last-client-frame-p frame))
        (when (yes-or-no-p (ch-emacs-config-daemon--last-frame-prompt))
          (funcall orig frame force))
      (funcall orig frame force))))

(defun ch-emacs-config-daemon--owns-last-client-frames-p (proc)
  "Whether client PROC owns every client frame this daemon has left.
Nil for a frameless client (an $EDITOR or --eval connection finishing
is not a frame closing) and whenever another client still has a frame."
  (let (mine others)
    (dolist (f (frame-list))
      (when (ch-emacs-config-daemon--client-frame-p f)
        (if (eq (frame-parameter f 'client) proc)
            (setq mine t)
          (setq others t))))
    (and mine (not others))))

(defun ch-emacs-config-daemon--confirm-delete-client (orig proc &optional noframe)
  "Ask before a tainted daemon drops the blocking client owning its last frame.
\\[save-buffers-kill-terminal] and :qa! on a frame from a blocking
client (a tty frame, or emacsclient -c without -n) call
`server-delete-client', which clears each frame's `client' parameter
and tears the connection down before deleting the frame, so the
`delete-frame' gate cannot see or keep that frame.  This is the gate
for that path.  NOFRAME non-nil means `delete-frame' is already
deleting the client's last frame and has asked; do not ask twice."
  (if (and ch-emacs-config-daemon--tainted
           (daemonp)
           (not noframe)
           (processp proc)
           (ch-emacs-config-daemon--owns-last-client-frames-p proc))
      (when (yes-or-no-p (ch-emacs-config-daemon--last-frame-prompt))
        (funcall orig proc noframe))
    (funcall orig proc noframe)))

(when (daemonp)
  (advice-add 'delete-frame :around
              #'ch-emacs-config-daemon--confirm-delete-frame)
  (advice-add 'server-delete-client :around
              #'ch-emacs-config-daemon--confirm-delete-client))
