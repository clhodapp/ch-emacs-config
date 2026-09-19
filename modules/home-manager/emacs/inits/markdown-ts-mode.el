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

  ;; markdown-ts-mode counts the leading `#' characters and applies
  ;; `markdown-ts-heading-N' per level, but defines all six alike
  ;; (font-lock-function-name-face, bold), so an H1 and an H4 are
  ;; indistinguishable.  Give each level the colour the loaded theme
  ;; already picked for `outline-N', which is the same job in org and
  ;; outline buffers, so these follow a theme change instead of pinning
  ;; hex values here.
  ;;
  ;; Weight steps down once per level, which Monaspace can render because
  ;; it draws seven real weights.  Size reinforces the top three, where
  ;; the document's shape is; from the fourth the nesting is finer than
  ;; type size usefully renders, so those stay at body size and weight
  ;; alone continues the descent, ending below body weight so a deeply
  ;; nested heading cannot shout as loudly as the section containing it.
  ;;
  ;; A weight ramp needs a font that draws the intermediate weights.
  ;; Where only Regular and Bold exist, fontconfig rounds a request for
  ;; semibold to one of them and the ramp collapses into an arbitrary
  ;; split, which is what the previous two-weight font forced.
  ;;
  ;; sanityinc-tomorrow cycles six hues across eight outline levels, so
  ;; `outline-6' repeats `outline-1' blue.  Those two are never confusable
  ;; despite the shared hue: the first level is the heaviest weight at
  ;; half again the body size, the sixth is the lightest at body size.
  :custom-face
  (markdown-ts-heading-1 ((t (:inherit outline-1 :weight bold :height 1.4))))
  (markdown-ts-heading-2 ((t (:inherit outline-2 :weight semi-bold :height 1.25))))
  (markdown-ts-heading-3 ((t (:inherit outline-3 :weight medium :height 1.1))))
  (markdown-ts-heading-4 ((t (:inherit outline-4 :weight medium))))
  (markdown-ts-heading-5 ((t (:inherit outline-5 :weight normal))))
  (markdown-ts-heading-6 ((t (:inherit outline-6 :weight light))))
  ;; A setext heading (underlined by === or ---) is level 1 or 2, but
  ;; the mode has one face for both and its default points at level 1.
  (markdown-ts-setext-heading ((t (:inherit markdown-ts-heading-1))))

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
