;; SPDX-License-Identifier: MIT
;; init nerd-icons + integrations (completion, corfu, dired)
(declare-function nerd-icons-corfu-formatter "nerd-icons-corfu")

;; The base library loads on demand, dragged in by the integrations below.
;; Icons are tagged with `nerd-icons-font-family' by name, and its default
;; ("Symbols Nerd Font Mono") is the icons-only font, installed alongside
;; the text font rather than patched into it.  The Mono variant keeps icons
;; one cell wide, which dired's column alignment assumes.  Leaving the
;; default in place means the text font is a free choice: it carries no
;; icons, and changing it does not require finding a patched build of it.
(use-package nerd-icons)

(use-package nerd-icons-completion
  ;; `nerd-icons-completion-marginalia-setup' toggles the mode in sync with
  ;; marginalia, which the vertico bundle enables after this init runs.
  :hook (marginalia-mode . nerd-icons-completion-marginalia-setup))

(use-package nerd-icons-corfu
  :demand t
  :after corfu
  :config
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

(use-package nerd-icons-dired
  :hook (dired-mode . nerd-icons-dired-mode))
