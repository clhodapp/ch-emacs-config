;; SPDX-License-Identifier: MIT
;; init markdown-ts-mode

;; use-package's compile-time load runs inside `eval-when-compile', so the
;; byte compiler flags the function behind the `evil-define-key' macro as
;; possibly missing at runtime; declare it (ghostel.el precedent).
(declare-function evil-define-key* "evil-core")
;; Same reason for the command bound below: it is defined by
;; markdown-ts-mode, which has not loaded when this file is compiled,
;; and it carries no autoload cookie the way markdown-table-fix-dwim
;; does.
(declare-function markdown-ts-toggle-hide-markup "markdown-ts-mode")

(use-package markdown-ts-mode
  :mode "\\.md\\'"
  :config
  ;; Markdown's "compile": normalize the buffer's pipe tables.  Holds
  ;; the render/preview slot until a real preview mode is added.
  (evil-define-key 'motion markdown-ts-mode-map
    (kbd "<leader> c") #'markdown-table-fix-dwim
    ;; Under the toggles prefix with the other display toggles, `m' for
    ;; markup: stop displaying the heading hashes, emphasis markers,
    ;; code-span backticks, and link brackets and destinations.
    ;; Upstream binds this to C-c C-x RET.
    (kbd "<leader> t m") #'markdown-ts-toggle-hide-markup))
