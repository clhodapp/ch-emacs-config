;; SPDX-License-Identifier: MIT
;; init envrc
(use-package envrc
  ;; direnv runs a process per buffer; a mirror child has no use for it.
  :unless (bound-and-true-p ch/mirror-profile)
  :commands
  (envrc-mode
   envrc-file-mode
   envrc-global-mode)
  :hook ((after-init) . envrc-global-mode)
  :custom
  (envrc-show-summary-in-minibuffer nil "disable verbose logging from direnv"))
