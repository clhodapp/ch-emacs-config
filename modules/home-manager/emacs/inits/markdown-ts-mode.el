;; SPDX-License-Identifier: MIT
;; init markdown-ts-mode

;; use-package's compile-time load runs inside `eval-when-compile', so the
;; byte compiler flags the function behind the `evil-define-key' macro as
;; possibly missing at runtime; declare it (ghostel.el precedent).
(declare-function evil-define-key* "evil-core")

(use-package markdown-ts-mode
  :mode "\\.md\\'"

  ;; markdown-ts-mode counts the leading `#' characters and applies
  ;; `markdown-ts-heading-N' per level, but defines all six alike
  ;; (font-lock-function-name-face, bold), so an H1 and an H4 are
  ;; indistinguishable.  Give each level the colour the loaded theme
  ;; already picked for `outline-N', which is the same job in org and
  ;; outline buffers, so these follow a theme change instead of pinning
  ;; hex values here.  Size carries the top of the hierarchy, where the
  ;; document's shape is; from the fourth level down the nesting is
  ;; finer than type size usefully renders, so colour alone separates
  ;; them and the text stays at body size.
  ;;
  ;; sanityinc-tomorrow cycles six hues across eight outline levels, so
  ;; `outline-6' repeats `outline-1' blue; the first level's larger text
  ;; is what keeps those two apart.  Levels five and six are rare enough
  ;; in practice that reaching past the theme for a seventh colour would
  ;; cost more than the collision does.
  :custom-face
  (markdown-ts-heading-1 ((t (:inherit outline-1 :weight bold :height 1.4))))
  (markdown-ts-heading-2 ((t (:inherit outline-2 :weight bold :height 1.25))))
  (markdown-ts-heading-3 ((t (:inherit outline-3 :weight bold :height 1.1))))
  (markdown-ts-heading-4 ((t (:inherit outline-4 :weight bold))))
  (markdown-ts-heading-5 ((t (:inherit outline-5 :weight bold))))
  (markdown-ts-heading-6 ((t (:inherit outline-6 :weight bold))))
  ;; A setext heading (underlined by === or ---) is level 1 or 2, but
  ;; the mode has one face for both and its default points at level 1.
  (markdown-ts-setext-heading ((t (:inherit markdown-ts-heading-1))))

  :config
  ;; Markdown's "compile": normalize the buffer's pipe tables.  Holds
  ;; the render/preview slot until a real preview mode is added.
  (evil-define-key 'motion markdown-ts-mode-map
    (kbd "<leader> c") #'markdown-table-fix-dwim))
