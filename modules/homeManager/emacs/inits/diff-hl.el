;; SPDX-License-Identifier: MIT
;; init diff-hl
(declare-function diff-hl-magit-post-refresh "diff-hl")
(declare-function diff-hl-flydiff-mode "diff-hl-flydiff")

(use-package diff-hl
  :demand t

  :commands
  (global-diff-hl-mode
   diff-hl-magit-post-refresh)

  ;; diff-hl >= 1.11 needs only the post-refresh hook; the pre-refresh
  ;; counterpart is obsolete.
  :hook (magit-post-refresh . diff-hl-magit-post-refresh)

  :config
  (global-diff-hl-mode 1)
  ;; Diff against the index as you type, not only after saving.
  (diff-hl-flydiff-mode 1))

;; diff-hl owns the left fringe; keep flymake's indicators on the right
;; fringe so a changed line with a diagnostic shows both.
(use-package flymake
  :custom
  (flymake-fringe-indicator-position 'right-fringe))
