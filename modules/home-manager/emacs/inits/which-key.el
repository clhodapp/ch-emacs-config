;; SPDX-License-Identifier: MIT
;; init which-key (built-in since Emacs 30)
(use-package which-key

  :demand t

  :commands
  which-key-mode

  :custom
  (which-key-idle-delay 0.5 "show popup after half a second")
  (which-key-idle-secondary-delay 0.05)
  (which-key-sort-order 'which-key-key-order-alpha)
  (which-key-max-description-length 40)

  :config
  ;; help-map's `4' is an anonymous keymap (info-other-window etc.), so
  ;; which-key shows it as an unnamed +prefix without a label
  (which-key-add-key-based-replacements "C-h 4" "other-window")
  (which-key-mode 1))
