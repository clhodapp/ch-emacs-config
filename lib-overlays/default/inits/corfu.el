;; SPDX-License-Identifier: MIT
;; init corfu + cape
(use-package corfu
  :demand t

  :commands
  global-corfu-mode

  :custom
  (corfu-auto t)

  :config
  (global-corfu-mode 1))

(use-package cape
  :demand t

  :commands
  (cape-dabbrev
   cape-file)

  :config
  (add-hook 'completion-at-point-functions #'cape-dabbrev)
  (add-hook 'completion-at-point-functions #'cape-file))
