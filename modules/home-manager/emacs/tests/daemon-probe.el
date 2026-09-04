;;; daemon-probe.el --- Startup health probe for the daemon smoke test -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Loaded into a freshly started daemon via emacsclient.  Real startup
;; catches init errors (recording `init-file-had-error') and use-package
;; demotes :init/:config errors to warnings, so a daemon can come up
;; "successfully" with a broken config.  The probe checks all three
;; signals and returns a verdict string the check script matches on.

;;; Code:

(defun ch-emacs-config-daemon-probe ()
  "Return \"OK\" when the daemon booted the shared init cleanly."
  (let ((warnings (and (get-buffer "*Warnings*")
                       (with-current-buffer "*Warnings*"
                         (buffer-substring-no-properties (point-min) (point-max))))))
    (cond (init-file-had-error
           "FAIL: init-file-had-error is set")
          ((not (featurep 'ch-emacs-config-default))
           "FAIL: ch-emacs-config-default was not loaded during startup")
          ;; warning.el renders entries as "ICON Error (type): message";
          ;; the icon prefix varies with display capability, so match the
          ;; level word after start-of-line or whitespace instead of bol.
          ((and warnings
                (string-match-p "\\(?:^\\|\\s-\\)\\(?:Error\\|Emergency\\) (" warnings))
           (concat "FAIL: error-level warnings during startup:\n" warnings))
          (t "OK"))))

;;; daemon-probe.el ends here
