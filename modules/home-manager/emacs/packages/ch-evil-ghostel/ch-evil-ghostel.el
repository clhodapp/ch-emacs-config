;;; ch-evil-ghostel.el --- Local additions to evil-ghostel -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Four behaviors layered on upstream `evil-ghostel', using ghostel's
;; public API only so upstream can move without this file moving with
;; it.  Everything here is additive: no upstream definition is
;; replaced, and each piece degrades to upstream's behavior if its
;; advice is removed.
;;
;; This file replaces a vendored fork of evil-ghostel.el.  That fork
;; carried three further changes which upstream has since made
;; unnecessary: two were compatibility shims for renames (the cursor
;; style function, the redraw signature gaining FORCE-SYNC), and the
;; third fixed an `evil-change' advice that upstream replaced with its
;; own `evil-ghostel-change' command.
;;
;; What upstream gates on `evil-ghostel--prompt-active-p' is deliberately
;; off in alt-screen mode, where a fullscreen TUI owns the screen.  Two
;; of the behaviors here are precisely about that case: a TUI still
;; accepts bracketed paste and still has a use for the kill ring.

;;; Code:

(require 'evil)
(require 'ghostel)
(require 'evil-ghostel)
(require 'ghostel-funcs)

(declare-function ghostel-alt-screen-p "ghostel")
(declare-function ghostel-paste-string "ghostel")
(declare-function ghostel-send-key "ghostel")
(declare-function ghostel-yank "ghostel")
(declare-function ch/ghostel-send-escape "ghostel-funcs")

(defun ch/evil-ghostel--tui-p ()
  "Return non-nil when a fullscreen TUI is running in this buffer.
Upstream's own predicates all exclude this state, since its commands
edit a shell's input line and a TUI has none.  The behaviors below
apply here for the opposite reason: a TUI is exactly where evil's
buffer-editing commands are useless and the PTY should get the keys."
  (and (bound-and-true-p evil-ghostel-mode)
       (ghostel-alt-screen-p)))

;;; Paste into a TUI
;;
;; Upstream's `evil-ghostel-paste-after' / `-before' route to the PTY
;; only while the shell's line editor is live, and fall back to evil's
;; buffer paste otherwise.  In a TUI that fallback inserts text into the
;; terminal buffer, where it is not input and merely corrupts the
;; display.  Bracketed paste reaches the TUI instead.

(defun ch/evil-ghostel--tui-paste (count register)
  "Bracketed-paste REGISTER (or the last kill) COUNT times into a TUI.
No cursor synchronization: the TUI owns the cursor, so there is no
input line to move point along."
  (let ((text (if register (evil-get-register register) (current-kill 0))))
    (when text
      (dotimes (_ (prefix-numeric-value count))
        (ghostel-paste-string text)))))

(defun ch/evil-ghostel--around-paste (orig-fn &optional count register yank-handler)
  "Paste into a TUI when one is running, else let ORIG-FN decide.
ORIG-FN is `evil-ghostel-paste-after' or `-before', called with COUNT,
REGISTER and YANK-HANDLER.  Both take the same arguments and both want
the same treatment here, since a TUI has no before-or-after cursor cell
to distinguish."
  (if (ch/evil-ghostel--tui-p)
      (ch/evil-ghostel--tui-paste count register)
    (funcall orig-fn count register yank-handler)))

;;; Kill-ring yank inside a TUI
;;
;; Upstream passes C-y through to the PTY whenever the terminal is live
;; in semi-char mode, which is readline's yank.  In a TUI readline is not
;; running, so C-y usually does nothing useful; sending the Emacs kill
;; ring is more likely what was meant.

(defun ch/evil-ghostel-yank-or-passthrough ()
  "Yank the Emacs kill ring into a TUI; otherwise send C-y to the PTY.
Outside alt-screen this is what upstream's passthrough does, so
readline's own C-y still works at a shell prompt.  Calling upstream's
command by name is not an option: this binding replaces it in
`evil-ghostel-mode-map', so looking the key up again would find this
function and recurse."
  (interactive)
  (cond
   ((ch/evil-ghostel--tui-p) (ghostel-yank))
   ((evil-ghostel--prompt-active-p) (ghostel-send-key "y" "ctrl"))
   (t (let* ((vec (kbd "C-y"))
             (local (current-local-map))
             (cmd (or (and local (lookup-key local vec))
                      (lookup-key evil-insert-state-map vec))))
        (when (commandp cmd)
          (call-interactively cmd))))))

;;; Arrow keys in insert state
;;
;; Evil binds the arrow keys to its own motions in insert state, which
;; move point in the buffer rather than reaching the shell.  In a
;; terminal the arrows are how history and line editing work, so they
;; belong to the PTY whenever it is listening.

(defun ch/evil-ghostel--passthrough-arrow (direction)
  "Send arrow DIRECTION to the PTY, or run evil's binding for it.
DIRECTION is a ghostel key name: \"up\", \"down\", \"left\" or \"right\".
Passes through while the shell's line editor is live and inside a TUI;
in line mode the buffer holds the input as ordinary text, so evil's
motion is the right thing and runs instead."
  (if (or (evil-ghostel--prompt-active-p) (ch/evil-ghostel--tui-p))
      (ghostel-send-key direction)
    (let* ((vec (kbd (format "<%s>" direction)))
           (local (current-local-map))
           (cmd (or (and local (lookup-key local vec))
                    (lookup-key evil-insert-state-map vec))))
      (when (commandp cmd)
        (call-interactively cmd)))))

;;; Wiring

(defvar ch/evil-ghostel--advice
  '((evil-ghostel-paste-after . ch/evil-ghostel--around-paste)
    (evil-ghostel-paste-before . ch/evil-ghostel--around-paste))
  "Upstream commands advised by this package, as (SYMBOL . ADVICE).")

;;;###autoload
(define-minor-mode ch/evil-ghostel-mode
  "Local additions to `evil-ghostel'.
Enable alongside `evil-ghostel-mode'; each behavior checks for itself
whether it applies, so this is safe to leave on."
  :global t
  :group 'ghostel
  (if ch/evil-ghostel-mode
      (pcase-dolist (`(,sym . ,fn) ch/evil-ghostel--advice)
        (advice-add sym :around fn))
    (pcase-dolist (`(,sym . ,fn) ch/evil-ghostel--advice)
      (advice-remove sym fn))))

;; Keys go in upstream's own map, so they follow `evil-ghostel-mode' on
;; and off with everything else and need no map of their own.
;;
;; S-ESC sends a literal ESC.  Plain ESC belongs to evil (see
;; `evil-ghostel-escape'), and upstream's own
;; `evil-ghostel-toggle-send-escape' flips that routing for a whole
;; buffer; this is the one-off, for the ESC a TUI actually wants.  It is
;; only distinct from plain ESC in a graphical frame, since a tty
;; delivers Shift-ESC as ESC.  The sender itself lives in ghostel-funcs.
(evil-define-key* '(normal visual insert) evil-ghostel-mode-map
                  (kbd "S-<escape>") #'ch/ghostel-send-escape)

(evil-define-key* 'insert evil-ghostel-mode-map
                  (kbd "C-y") #'ch/evil-ghostel-yank-or-passthrough
                  [remap yank] #'ghostel-yank)

(dolist (dir '("up" "down" "left" "right"))
  (let ((d dir))
    (evil-define-key* 'insert evil-ghostel-mode-map
                      (kbd (format "<%s>" d))
                      (defalias (intern (format "ch/evil-ghostel--passthrough-arrow-%s" d))
                        (lambda ()
                          (interactive)
                          (ch/evil-ghostel--passthrough-arrow d))
                        (format "Send <%s> to the terminal or fall back to evil." d)))))

(provide 'ch-evil-ghostel)
;;; ch-evil-ghostel.el ends here
