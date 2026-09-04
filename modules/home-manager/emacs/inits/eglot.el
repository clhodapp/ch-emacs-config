;; SPDX-License-Identifier: MIT
;; init eglot

;; This bundle section compiles before evil's (alphabetical aggregation), so
;; the `evil-define-key' macro isn't known yet; load it for expansion. At
;; runtime the order is inverted: evil (:demand t) is up before anything can
;; drag eglot in.
(eval-when-compile (require 'evil))

;; use-package's compile-time load runs inside `eval-when-compile', so the
;; byte compiler flags the functions behind the `evil-define-key' macro and
;; its bound commands as possibly missing at runtime; declare them
;; (ghostel.el precedent).
(declare-function evil-define-key* "evil-core")
(declare-function eglot-code-actions "eglot")
(declare-function eglot-find-implementation "eglot")
(declare-function eglot-find-typeDefinition "eglot")
(declare-function eglot-format "eglot")
(declare-function eglot-inlay-hints-mode "eglot")
(declare-function eglot-rename "eglot")
(declare-function consult-eglot-symbols "consult-eglot")
(declare-function consult-imenu "consult-imenu")
(declare-function consult-imenu-multi "consult-imenu")
(declare-function flymake-show-buffer-diagnostics "flymake")
(declare-function flymake-show-project-diagnostics "flymake")

(use-package eglot
  :hook ((nix-ts-mode
          python-base-mode
          markdown-ts-mode
          js-base-mode
          typescript-ts-base-mode
          json-ts-mode
          mermaid-ts-mode)
         . eglot-ensure)

  :config
  ;; eglot derives the LSP languageId from an entry's mode name, stripping
  ;; only "(-ts)?-mode"; an entry keyed on python-base-mode therefore sends
  ;; languageId "python-base", which ty rejects by silently reporting zero
  ;; diagnostics. Upstream can't strip "-base" generically (a base mode may
  ;; span several languageIds, e.g. typescript-ts-base-mode covers
  ;; "typescript" and "typescriptreact"), but python's hierarchy is
  ;; unambiguous; pin it via eglot's symbol-property escape hatch so the
  ;; server-programs entry can stay keyed on the bare base mode.
  (put 'python-base-mode 'eglot-language-id "python")

  ;; Scoped to eglot-mode-map so `<leader> l' only exists in managed
  ;; buffers; the prefix title is bound in the same map for the same
  ;; reason.
  (evil-define-key 'motion eglot-mode-map
    (kbd "<leader> l") (cons "lsp" (make-sparse-keymap))
    (kbd "<leader> l a") #'eglot-code-actions
    ;; eglot has no find-definition command of its own; definitions go
    ;; through its xref backend. Unlike `eglot-find-implementation', this
    ;; works on servers without textDocument/implementation (e.g. Python's).
    (kbd "<leader> l d") #'xref-find-definitions
    (kbd "<leader> l e") #'flymake-show-buffer-diagnostics
    (kbd "<leader> l E") #'flymake-show-project-diagnostics
    (kbd "<leader> l f") #'eglot-format
    (kbd "<leader> l h") #'eldoc-doc-buffer
    ;; Buffer outline vs workspace query: `l i'/`l I' (imenu, fed by the
    ;; server's documentSymbol) complement `l s' (consult-eglot-symbols).
    (kbd "<leader> l i") #'consult-imenu
    (kbd "<leader> l I") #'consult-imenu-multi
    (kbd "<leader> l m") #'eglot-find-implementation
    (kbd "<leader> l r") #'eglot-rename
    (kbd "<leader> l s") #'consult-eglot-symbols
    (kbd "<leader> l t") #'eglot-find-typeDefinition
    (kbd "<leader> l R") #'xref-find-references
    (kbd "<leader> t i") #'eglot-inlay-hints-mode))
