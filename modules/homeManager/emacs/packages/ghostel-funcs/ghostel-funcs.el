;;; ghostel-funcs --- extra functions to use with ghostel-mode -*- lexical-binding: t -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:

;;; Code:

(require 'ghostel)

(defvar evil-ghostel--escape-mode nil
  "Forward declare for `evil-ghostel'; buffer-local when `evil-ghostel-mode' is on.")

(declare-function ghostel--start "ghostel" (context name &optional arg))
(declare-function ghostel--on-user-input "ghostel" ())

;;;###autoload
(defun ch/ghostel--inject-buffer-name-env ()
  "Inject `EMACS_BUFFER_NAME' before the shell process spawns."
  (setenv "EMACS_BUFFER_NAME" (buffer-name)))

;;;###autoload
(defun ch/ghostel-send-escape ()
  "Send escape to the ghostel terminal."
  (interactive)
  (ghostel-send-key "escape"))

;;;###autoload
(defun ch/ghostel-send-C-x ()
  "Send \\`C-x' to the ghostel terminal.
Upstream reserves \\`C-x' for Emacs (`ghostel-keymap-exceptions'), so
programs that need it — nano's exit key, for one — can't receive it
without an explicit sender."
  (interactive)
  (ghostel--on-user-input)
  (ghostel-send-key "x" "ctrl"))

;;;###autoload
(defun ch/ghostel-toggle-escape-routing ()
  "Toggle ESC routing between Evil and the ghostel terminal."
  (interactive)
  (setq evil-ghostel--escape-mode
        (if (eq evil-ghostel--escape-mode 'evil) 'terminal 'evil))
  (message "ESC → %s"
           (if (eq evil-ghostel--escape-mode 'evil) "evil" "terminal")))

;;;###autoload
(defun ch/ghostel-called (name)
  "Create or switch to the ghostel buffer called NAME.
A ghostel identity is an alist whose mandatory `kind' says what
created the buffer; `name' scopes a plain terminal to a label, which
is what this command asks for.  `ghostel--start' finds the matching
slot or creates it, so the name is both the prompt answer and the
buffer name."
  (interactive (list (read-from-minibuffer "ghostel called: ")))
  (ghostel--start `((kind . term) (name . ,name)) name))

;;;###autoload
(defun ch/ghostel-send-buffer-env ()
  "Send the `EMACS_BUFFER_NAME' export command to ghostel.
This is intended to be called by a shell function running `read -s`."
  (interactive)
  (let ((cmd (format "export EMACS_BUFFER_NAME=%s"
                     (shell-quote-argument (buffer-name)))))
    (ghostel-send-string (concat cmd "\n"))))

(provide 'ghostel-funcs)
;;; ghostel-funcs.el ends here
