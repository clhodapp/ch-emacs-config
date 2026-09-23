;;; ch-evil-ghostel-ert.el --- Tests for ch-evil-ghostel -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; The point of these tests is the interface, not the terminal.  This
;; package layers five behaviors on upstream evil-ghostel using only
;; ghostel's public functions, and the value of that is that upstream
;; can move without dragging a vendored fork along.  So each test
;; records what reached ghostel: the function called and its arguments.
;; A rename or an arity change upstream fails these, which is the whole
;; reason they exist.
;;
;; Real ghostel is loaded (the flake check puts it on the load path), so
;; the names below are resolved against the actual package.  Only the
;; four functions that would drive a live PTY are stubbed, and each
;; stub keeps the real one's argument list, so a signature drift shows
;; up as a wrong-number-of-arguments failure rather than silence.

;;; Code:

(require 'ert)
(require 'evil)
(require 'ghostel)
(require 'evil-ghostel)
(require 'ch-evil-ghostel)

(defvar ch-evil-ghostel-tests--sent nil
  "Calls captured from the stubbed ghostel API, oldest first.")

(defun ch-evil-ghostel-tests--record (&rest call)
  "Append CALL to `ch-evil-ghostel-tests--sent'."
  (setq ch-evil-ghostel-tests--sent
        (append ch-evil-ghostel-tests--sent (list call))))

(defmacro ch-evil-ghostel-tests--with-terminal (alt-screen &rest body)
  "Run BODY with ghostel's output functions captured.
ALT-SCREEN is the value `ghostel-alt-screen-p' reports, so a test picks
between a fullscreen TUI and an ordinary shell prompt.  Bindings are
`cl-letf' overrides on the real symbols: if upstream renames one of
these, the override no longer refers to anything the code calls and the
assertion fails."
  (declare (indent 1))
  `(let ((ch-evil-ghostel-tests--sent nil)
         (evil-ghostel-mode t))
     (cl-letf (((symbol-function 'ghostel-alt-screen-p)
                (lambda () ,alt-screen))
               ((symbol-function 'ghostel-send-key)
                (lambda (key-name &optional mods)
                  (ch-evil-ghostel-tests--record 'send-key key-name mods)))
               ((symbol-function 'ghostel-paste-string)
                (lambda (string)
                  (ch-evil-ghostel-tests--record 'paste-string string)))
               ((symbol-function 'ghostel-yank)
                (lambda () (ch-evil-ghostel-tests--record 'yank)))
               ((symbol-function 'evil-ghostel--prompt-active-p)
                (lambda () (not ,alt-screen))))
       ,@body)))

;;; The public API this package is written against
;;
;; If any of these is missing or takes different arguments, every
;; behavior below is broken.  Checking it directly says so in one line
;; instead of four confusing failures.

(ert-deftest ch-evil-ghostel-public-api-present ()
  "Every ghostel function this package calls exists, with the arity used."
  (dolist (entry '((ghostel-alt-screen-p . 0)
                   (ghostel-send-key . 1)
                   (ghostel-paste-string . 1)
                   (ghostel-readonly-exit . 0)
                   (ghostel-yank . 0)))
    (let* ((sym (car entry))
           (wanted (cdr entry))
           (arity (progn (should (fboundp sym)) (func-arity sym))))
      (should (<= (car arity) wanted))
      (should (or (eq (cdr arity) 'many) (>= (cdr arity) wanted))))))

(ert-deftest ch-evil-ghostel-upstream-hooks-present ()
  "The upstream definitions this package advises and extends exist."
  (should (fboundp 'evil-ghostel-paste-after))
  (should (fboundp 'evil-ghostel-paste-before))
  (should (fboundp 'evil-ghostel--prompt-active-p))
  (should (keymapp evil-ghostel-mode-map))
  ;; Upstream owns the buffer-wide ESC routing; S-ESC is the one-off
  ;; beside it, so if this command disappears the binding is redundant.
  (should (fboundp 'evil-ghostel-toggle-send-escape)))

;;; Paste into a TUI

(ert-deftest ch-evil-ghostel-paste-reaches-tui ()
  "In alt-screen, paste bracket-pastes instead of editing the buffer."
  (ch-evil-ghostel-tests--with-terminal t
    (with-temp-buffer
      (kill-new "hello")
      (ch/evil-ghostel--around-paste #'ignore 1 nil nil)
      (should (equal ch-evil-ghostel-tests--sent '((paste-string "hello"))))
      ;; The terminal buffer itself is untouched: inserting there would
      ;; corrupt the TUI's display rather than feed it input.
      (should (equal (buffer-string) "")))))

(ert-deftest ch-evil-ghostel-paste-repeats-with-count ()
  "A count pastes that many times."
  (ch-evil-ghostel-tests--with-terminal t
    (kill-new "x")
    (ch/evil-ghostel--around-paste #'ignore 3 nil nil)
    (should (equal ch-evil-ghostel-tests--sent
                   '((paste-string "x") (paste-string "x") (paste-string "x"))))))

(ert-deftest ch-evil-ghostel-paste-honors-register ()
  "An explicit register is pasted rather than the last kill."
  (ch-evil-ghostel-tests--with-terminal t
    (kill-new "from-kill-ring")
    (evil-set-register ?a "from-register")
    (ch/evil-ghostel--around-paste #'ignore 1 ?a nil)
    (should (equal ch-evil-ghostel-tests--sent
                   '((paste-string "from-register"))))))

(ert-deftest ch-evil-ghostel-paste-defers-outside-alt-screen ()
  "At a shell prompt upstream's own paste runs untouched."
  (ch-evil-ghostel-tests--with-terminal nil
    (let ((called nil))
      (ch/evil-ghostel--around-paste
       (lambda (&rest args) (setq called args)) 2 ?b 'handler)
      (should (equal called '(2 ?b handler)))
      (should (null ch-evil-ghostel-tests--sent)))))

;;; Kill-ring yank inside a TUI

(ert-deftest ch-evil-ghostel-yank-in-tui ()
  "C-y sends the Emacs kill ring to a TUI, which has no readline."
  (ch-evil-ghostel-tests--with-terminal t
    (call-interactively #'ch/evil-ghostel-yank-or-passthrough)
    (should (equal ch-evil-ghostel-tests--sent '((yank))))))

(ert-deftest ch-evil-ghostel-yank-passes-through-at-prompt ()
  "At a live prompt C-y reaches the shell, so readline's yank still works."
  (ch-evil-ghostel-tests--with-terminal nil
    (call-interactively #'ch/evil-ghostel-yank-or-passthrough)
    (should (equal ch-evil-ghostel-tests--sent '((send-key "y" "ctrl"))))))

;;; Arrow keys in insert state

(ert-deftest ch-evil-ghostel-arrows-reach-a-tui ()
  "Arrows go to the PTY in alt-screen, where they drive the TUI."
  (ch-evil-ghostel-tests--with-terminal t
    (dolist (dir '("up" "down" "left" "right"))
      (ch/evil-ghostel--passthrough-arrow dir))
    (should (equal ch-evil-ghostel-tests--sent
                   '((send-key "up" nil) (send-key "down" nil)
                     (send-key "left" nil) (send-key "right" nil))))))

(ert-deftest ch-evil-ghostel-arrows-reach-a-live-prompt ()
  "Arrows go to the PTY at a shell prompt, where they are history and editing."
  (ch-evil-ghostel-tests--with-terminal nil
    (cl-letf (((symbol-function 'evil-ghostel--prompt-active-p) (lambda () t)))
      (ch/evil-ghostel--passthrough-arrow "up")
      (should (equal ch-evil-ghostel-tests--sent '((send-key "up" nil)))))))

(ert-deftest ch-evil-ghostel-arrows-fall-back-in-line-mode ()
  "With no live prompt and no TUI, evil's own binding runs instead."
  (ch-evil-ghostel-tests--with-terminal nil
    (let ((ran nil))
      (cl-letf (((symbol-function 'evil-ghostel--prompt-active-p) (lambda () nil)))
        (let ((map (make-sparse-keymap)))
          (define-key map (kbd "<up>")
                      (lambda () (interactive) (setq ran t)))
          (with-temp-buffer
            (use-local-map map)
            (ch/evil-ghostel--passthrough-arrow "up"))))
      (should ran)
      (should (null ch-evil-ghostel-tests--sent)))))

;;; ESC leaves copy mode

(ert-deftest ch-evil-ghostel-escape-exits-readonly ()
  "In copy or Emacs mode, where the buffer is read-only, ESC runs ghostel's exit."
  (let ((exited nil) (forced nil))
    (cl-letf (((symbol-function 'ghostel-readonly-exit)
               (lambda () (setq exited t)))
              ((symbol-function 'evil-force-normal-state)
               (lambda () (setq forced t))))
      (with-temp-buffer
        (setq buffer-read-only t)
        (call-interactively #'ch/evil-ghostel-escape-or-readonly-exit)))
    (should exited)
    (should-not forced)))

(ert-deftest ch-evil-ghostel-escape-keeps-evil-meaning-when-live ()
  "With the terminal live, ESC still does what normal state binds it to."
  (let ((exited nil) (forced nil))
    (cl-letf (((symbol-function 'ghostel-readonly-exit)
               (lambda () (setq exited t)))
              ((symbol-function 'evil-force-normal-state)
               (lambda () (setq forced t))))
      (with-temp-buffer
        (call-interactively #'ch/evil-ghostel-escape-or-readonly-exit)))
    (should forced)
    (should-not exited)))

;;; Bindings

(ert-deftest ch-evil-ghostel-bindings-installed ()
  "The keys this package claims are bound in upstream's own map.
Living in `evil-ghostel-mode-map' is what makes them follow
`evil-ghostel-mode' on and off without a keymap of this package's own."
  (should (eq (evil-lookup-key
               (evil-get-auxiliary-keymap evil-ghostel-mode-map 'insert)
               (kbd "C-y"))
              #'ch/evil-ghostel-yank-or-passthrough))
  (should (eq (evil-lookup-key
               (evil-get-auxiliary-keymap evil-ghostel-mode-map 'normal)
               (kbd "S-<escape>"))
              #'ch/ghostel-send-escape))
  (should (eq (evil-lookup-key
               (evil-get-auxiliary-keymap evil-ghostel-mode-map 'normal)
               (kbd "<escape>"))
              #'ch/evil-ghostel-escape-or-readonly-exit))
  (dolist (dir '("up" "down" "left" "right"))
    (should (commandp
             (evil-lookup-key
              (evil-get-auxiliary-keymap evil-ghostel-mode-map 'insert)
              (kbd (format "<%s>" dir)))))))

(ert-deftest ch-evil-ghostel-mode-toggles-advice ()
  "Enabling the mode installs the paste advice; disabling removes it."
  (let ((ch/evil-ghostel-mode nil))
    (ch/evil-ghostel-mode 1)
    (should (advice-member-p #'ch/evil-ghostel--around-paste
                             'evil-ghostel-paste-after))
    (should (advice-member-p #'ch/evil-ghostel--around-paste
                             'evil-ghostel-paste-before))
    (ch/evil-ghostel-mode -1)
    (should-not (advice-member-p #'ch/evil-ghostel--around-paste
                                 'evil-ghostel-paste-after))
    (should-not (advice-member-p #'ch/evil-ghostel--around-paste
                                 'evil-ghostel-paste-before))))

(provide 'ch-evil-ghostel-ert)
;;; ch-evil-ghostel-ert.el ends here
