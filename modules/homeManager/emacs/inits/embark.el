;; SPDX-License-Identifier: MIT
;; init embark
(use-package embark
  :commands (embark-act embark-dwim)
  :config
  (keymap-set embark-url-map "c" #'browse-url-chrome))

;; The minibuffer has no evil states, so the motion-state <leader> e e
;; can't reach embark-act on completion candidates (consult-gh
;; notification dismissal, per-candidate actions generally). C-. is
;; embark's conventional key; C-e -> embark-export in vertico-map is
;; the existing chord precedent.
(keymap-set minibuffer-local-map "C-." #'embark-act)

(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

(with-eval-after-load 'evil
  (ch/leader-prefix-title "e" "embark")
  (evil-global-set-key 'motion (kbd "<leader> e e") #'embark-act)
  (evil-global-set-key 'motion (kbd "<leader> e g") #'embark-dwim))
