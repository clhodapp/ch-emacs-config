;; SPDX-License-Identifier: MIT
;; init vertico + orderless + marginalia + consult
(use-package vertico
  :demand t
  :config
  (vertico-mode 1))

(use-package vertico-directory
  :demand t
  :after vertico
  :bind (:map vertico-map
         ("RET"           . vertico-directory-enter)
         ("DEL"           . vertico-directory-delete-char)
         ("S-<backspace>" . delete-backward-char)
         ("M-DEL"         . vertico-directory-delete-word)
         ("C-e"           . embark-export))
  :hook (rfn-eshadow-update-overlay . vertico-directory-tidy))

(use-package orderless
  :demand t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion)))))

(use-package marginalia
  :demand t
  :after vertico
  :config
  (marginalia-mode 1))

(use-package consult
  :commands
  (consult-buffer
   consult-find
   consult-grep
   consult-line-multi
   consult-recent-file
   consult-man
   consult-ripgrep
   consult-project-buffer))
