;; SPDX-License-Identifier: MIT
;; init plantuml-mode

;; use-package's compile-time load runs inside `eval-when-compile', so the
;; byte compiler flags the function behind the `evil-define-key' macro as
;; possibly missing at runtime; declare it (ghostel.el precedent).
(declare-function evil-define-key* "evil-core")
(declare-function plantuml-preview "plantuml-mode")

(use-package plantuml-mode
  :commands
  plantuml-mode

  :config
  (setq plantuml-default-exec-mode 'executable)
  (evil-define-key 'motion plantuml-mode-map
    (kbd "<leader> c") #'plantuml-preview))
