;; SPDX-License-Identifier: MIT
;; init envrc
(use-package envrc
  :commands
  (envrc-mode
   envrc-file-mode
   envrc-global-mode)
  :hook ((after-init) . envrc-global-mode)
  :custom
  (envrc-show-summary-in-minibuffer nil "disable verbose logging from direnv"))
