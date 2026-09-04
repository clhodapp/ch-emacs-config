;; SPDX-License-Identifier: MIT
;; init dired
(use-package dired
  :config
  ;; `a' (dired-find-alternate-file) is a fine bind here; drop the
  ;; disabled-command warning.
  (put 'dired-find-alternate-file 'disabled nil))
