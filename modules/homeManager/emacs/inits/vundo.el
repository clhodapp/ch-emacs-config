;; SPDX-License-Identifier: MIT
;; init vundo
(declare-function vundo "vundo")
(defvar vundo-unicode-symbols)

(use-package vundo
  :commands vundo
  :config
  (setq vundo-glyph-alist vundo-unicode-symbols))

(with-eval-after-load 'evil
  (evil-global-set-key 'motion (kbd "<leader> u") #'vundo))
