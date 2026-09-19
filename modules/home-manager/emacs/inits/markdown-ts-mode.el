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
  ;; hex values here.
  ;;
  ;; Size and weight together split the six levels into two groups.  The
  ;; first three are the document's shape, so they are bold and set
  ;; larger, stepping down.  From the fourth the nesting is finer than
  ;; type size usefully renders, so those stay at body size and drop to
  ;; normal weight: the loss of bold is itself the signal that the
  ;; heading is a minor one, and it keeps a deeply nested section from
  ;; shouting as loudly as the section that contains it.
  ;;
  ;; Weight is binary here rather than a ramp because Hack Nerd Font
  ;; ships only Regular and Bold (plus their italics).  A request for an
  ;; intermediate weight such as semibold is rounded to one of those by
  ;; fontconfig, so a graded four-step ramp would render as an arbitrary
  ;; split anyway.
  ;;
  ;; sanityinc-tomorrow cycles six hues across eight outline levels, so
  ;; `outline-6' repeats `outline-1' blue.  Those two are never confusable
  ;; despite the shared hue: the first level is bold and half again the
  ;; body size, the sixth is neither.
  :custom-face
  (markdown-ts-heading-1 ((t (:inherit outline-1 :weight bold :height 1.4))))
  (markdown-ts-heading-2 ((t (:inherit outline-2 :weight bold :height 1.25))))
  (markdown-ts-heading-3 ((t (:inherit outline-3 :weight bold :height 1.1))))
  (markdown-ts-heading-4 ((t (:inherit outline-4 :weight normal))))
  (markdown-ts-heading-5 ((t (:inherit outline-5 :weight normal))))
  (markdown-ts-heading-6 ((t (:inherit outline-6 :weight normal))))
  ;; A setext heading (underlined by === or ---) is level 1 or 2, but
  ;; the mode has one face for both and its default points at level 1.
  (markdown-ts-setext-heading ((t (:inherit markdown-ts-heading-1))))

  :config
  ;; Markdown's "compile": normalize the buffer's pipe tables.  Holds
  ;; the render/preview slot until a real preview mode is added.
  (evil-define-key 'motion markdown-ts-mode-map
    (kbd "<leader> c") #'markdown-table-fix-dwim))
