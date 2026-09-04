;; SPDX-License-Identifier: MIT
;; init treesit-fold
(declare-function global-treesit-fold-mode "treesit-fold")

(use-package treesit-fold
  :demand t

  :commands
  (global-treesit-fold-mode
   treesit-fold-close
   treesit-fold-close-all
   treesit-fold-open
   treesit-fold-open-all
   treesit-fold-open-recursively
   treesit-fold-toggle)

  :config
  (global-treesit-fold-mode 1))

(with-eval-after-load 'evil
  ;; evil's z-key fold commands (za zo zc zm zr) dispatch through
  ;; `evil-fold-list', which doesn't know treesit-fold; register it.
  ;; add-to-list prepends, so this entry wins in treesit-fold buffers.
  (add-to-list 'evil-fold-list
               '((treesit-fold-mode)
                 :open treesit-fold-open
                 :close treesit-fold-close
                 :open-rec treesit-fold-open-recursively
                 :open-all treesit-fold-open-all
                 :close-all treesit-fold-close-all
                 :toggle treesit-fold-toggle
                 :delete nil)))
