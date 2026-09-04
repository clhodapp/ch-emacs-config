;; SPDX-License-Identifier: MIT
;; init jinx
(declare-function jinx-correct "jinx")
(declare-function jinx-mode "jinx")

(use-package jinx
  :hook (emacs-startup . global-jinx-mode)

  :commands
  (jinx-mode
   jinx-correct
   global-jinx-mode)

  :custom
  (jinx-languages "en_US")
  ;; markdown-ts-mode derives from fundamental-mode, so the default
  ;; text/prog/conf predicate would skip the buffers that want spell
  ;; checking most.
  (global-jinx-modes '(text-mode prog-mode conf-mode markdown-ts-mode)))

(with-eval-after-load 'evil
  ;; vim's z= corrects the word at point; evil's stock binding is
  ;; ispell-word, which would drag in a second spellcheck system.
  (evil-global-set-key 'normal (kbd "z=") #'jinx-correct)
  (evil-global-set-key 'motion (kbd "<leader> t s") #'jinx-mode))
