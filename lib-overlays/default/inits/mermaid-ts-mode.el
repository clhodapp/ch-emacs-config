;; SPDX-License-Identifier: MIT
;; init mermaid-ts-mode

;; use-package's compile-time load runs inside `eval-when-compile', so the
;; byte compiler flags the function behind the `evil-define-key' macro as
;; possibly missing at runtime; declare it (ghostel.el precedent).
(declare-function evil-define-key* "evil-core")

(use-package mermaid-ts-mode
  :mode "\\.mmd\\'"
  :config
  (evil-define-key 'motion mermaid-ts-mode-map
    (kbd "<leader> c") #'mermaid-preview))
