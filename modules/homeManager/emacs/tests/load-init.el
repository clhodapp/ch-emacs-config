;;; load-init.el --- Batch smoke test for the shared init -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Loads the full ch-emacs-config-default init package the same way real
;; startup does (package activation triggers the autoload hook) and fails
;; on any error-level warning.  use-package wraps :init/:config bodies in
;; a condition-case that demotes runtime errors to warnings, so a plain
;; `require' can "succeed" with a broken config; trapping display-warning
;; is what makes this test strict.

;;; Code:

(defvar ch-emacs-config-test-errors nil)

(advice-add 'display-warning :before
            (lambda (type message &optional level &rest _)
              (when (memq level '(:error :emergency))
                (push (format "%s: %s" type message)
                      ch-emacs-config-test-errors))))

(package-activate-all)

(unless (featurep 'ch-emacs-config-default)
  (require 'ch-emacs-config-default))

(when ch-emacs-config-test-errors
  (message "Init load produced error-level warnings:")
  (dolist (err (nreverse ch-emacs-config-test-errors))
    (message "  %s" err))
  (kill-emacs 1))

(message "ch-emacs-config init loaded cleanly")

;;; load-init.el ends here
