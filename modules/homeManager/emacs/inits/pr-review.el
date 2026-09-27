;; SPDX-License-Identifier: MIT
;; init pr-review
(declare-function evil-define-key* "evil-core")
(declare-function pr-review-view-file "pr-review-action")
(declare-function pr-review-ediff-file "pr-review-action")
(defvar pr-review-mode-map)

(use-package pr-review
  :commands
  (pr-review
   pr-review-open
   pr-review-search
   pr-review-notification)

  :custom
  ;; (HOST . (FORGE-TYPE API-HOST USERNAME)). Both fields are explicit
  ;; so pr-review never consults ghub--username/ghub--host: the
  ;; delegation mode's overrides on those compare ghub's answers
  ;; against consult-gh's and prompt on mismatch — and the host method
  ;; doesn't normalize the api. prefix, so leaving API-HOST nil yields
  ;; a spurious "which account?" prompt (api.github.com vs github.com).
  ;; The token itself comes from the keyring via the mode's
  ;; ghub--token override; no auth-source entry exists.
  (pr-review-forges-alist '(("github.com" . (github "api.github.com" "clhodapp"))))

  :config
  ;; pr-review-mode-map inherits magit-section-mode-map, whose SPC
  ;; (scroll-up-command) evil-collection exposes at overriding priority
  ;; — the same shadowing magit.el works around. An explicit nil lets
  ;; lookup fall through to the motion-state <leader>. Do not use
  ;; `keymap-unset' with REMOVE: removal re-exposes the parent binding.
  ;; No replacement binding needed: evil's C-f/C-b/C-d/C-u scroll fine.
  (define-key pr-review-mode-map (kbd "SPC") nil)

  ;; Source access from a diff line, scoped to review buffers and
  ;; aligned with the same chords in magit modes: g f = the full file
  ;; at the line's revision (base for old-side, head otherwise),
  ;; g e = ediff base vs head of the file at point.
  (evil-define-key 'motion pr-review-mode-map
    (kbd "<leader> g f") #'pr-review-view-file
    (kbd "<leader> g e") #'pr-review-ediff-file))

;; Enumeration keys (g p / g n / g d / g i) live in consult-gh.el — the
;; front door — whose selections land in pr-review buffers via
;; consult-gh-with-pr-review-mode. pr-review-search and
;; pr-review-notification stay reachable by name.
(with-eval-after-load 'evil
  (ch/leader-prefix-title "g" "git")
  (evil-global-set-key 'motion (kbd "<leader> g r") #'pr-review))
