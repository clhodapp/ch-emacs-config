;;; mirror-profile.el --- Batch check of the mirror-profile guards -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Run after load-init.el has loaded the full init.  Asserts that the
;; inits which start external programs or long-lived helpers consult
;; `ch/mirror-profile': with it set, none of them registered itself;
;; without it, every one did.  The same file serves both runs, so the
;; check proves the assertions can fail rather than passing on hooks that
;; were never populated.  Hook membership is what is asserted, since in a
;; batch session `after-init-hook' and `emacs-startup-hook' have already
;; run before the init loads and the mode variables would stay nil either
;; way.

;;; Code:

(defvar ch/mirror-profile)
(defvar after-init-hook)
(defvar emacs-startup-hook)
(defvar nix-ts-mode-hook)
(defvar initial-buffer-choice)

(defun ch-emacs-config-test--registered ()
  "The spawners found registered, as a list of names."
  (delq nil
        (list (and (memq 'envrc-global-mode after-init-hook) "envrc")
              (and (memq 'global-jinx-mode emacs-startup-hook) "jinx")
              (and (memq 'eglot-ensure nix-ts-mode-hook) "eglot")
              (and (functionp initial-buffer-choice) "ghostel"))))

(let ((registered (ch-emacs-config-test--registered))
      (expected '("envrc" "jinx" "eglot" "ghostel")))
  (cond
   ((and (bound-and-true-p ch/mirror-profile) registered)
    (message "mirror profile set, but these registered anyway: %s"
             (mapconcat #'identity registered ", "))
    (kill-emacs 1))
   ((and (not (bound-and-true-p ch/mirror-profile))
         (not (equal (sort (copy-sequence registered) #'string<)
                     (sort (copy-sequence expected) #'string<))))
    (message "no mirror profile, but the spawners registered were %s (wanted %s)"
             (mapconcat #'identity registered ", ")
             (mapconcat #'identity expected ", "))
    (kill-emacs 1))
   (t
    (message "mirror-profile guards hold (profile %s)"
             (if (bound-and-true-p ch/mirror-profile) "on" "off")))))

;;; mirror-profile.el ends here
