;; SPDX-License-Identifier: MIT
;; init markdown-ts-mode

;; use-package's compile-time load runs inside `eval-when-compile', so the
;; byte compiler flags the function behind the `evil-define-key' macro as
;; possibly missing at runtime; declare it (ghostel.el precedent).
(declare-function evil-define-key* "evil-core")

(use-package markdown-ts-mode
  :mode "\\.md\\'"
  :config
  ;; Markdown's "compile": normalize the buffer's pipe tables.  Holds
  ;; the render/preview slot until a real preview mode is added.
  (evil-define-key 'motion markdown-ts-mode-map
    (kbd "<leader> c") #'markdown-table-fix-dwim))
