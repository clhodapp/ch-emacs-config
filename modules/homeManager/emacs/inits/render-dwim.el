;; SPDX-License-Identifier: MIT
;; init render-dwim

;; use-package's compile-time load runs inside `eval-when-compile', so the
;; byte compiler flags the function behind the binding as possibly
;; missing at runtime; declare it (mermaid-ts-mode.el precedent).
(declare-function evil-global-set-key "evil-core")

(use-package render-dwim
  :commands (render-dwim)
  :init
  ;; Global so it works in every buffer (ghostel terminals included);
  ;; modes with a native preview keep their own `<leader> c'.
  (with-eval-after-load 'evil
    (evil-global-set-key 'motion (kbd "<leader> r") #'render-dwim)))
