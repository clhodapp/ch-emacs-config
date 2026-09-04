;; SPDX-License-Identifier: MIT
;; init magit
(declare-function evil-define-key* "evil-core")
(declare-function magit-diff-show-or-scroll-up "magit-diff")
(declare-function magit-diff-visit-file "magit-diff")
(declare-function magit-ediff-dwim "magit-ediff")

(use-package magit
  :commands
  (magit-status
   magit-blame
   magit-log-current
   magit-diff-unstaged)

  :config
  ;; evil-collection makes magit's raw maps evil-overriding, which puts
  ;; magit's native SPC above the motion-state <leader> (the SPC entry in
  ;; `evil-collection-key-blacklist' only stops evil-collection's own
  ;; bindings). An explicit nil shadows magit's SPC — and the inherited
  ;; `scroll-up-command' from magit-section-mode-map behind it — so
  ;; lookup falls through to the leader. Scrolling stays on S-SPC / DEL.
  ;; Do not use `keymap-unset' with REMOVE: removal re-exposes the
  ;; parent binding at overriding priority.
  (define-key magit-mode-map (kbd "SPC") nil)
  (define-key magit-diff-mode-map (kbd "SPC") nil)
  (define-key magit-blame-read-only-mode-map (kbd "SPC") nil)
  ;; S-SPC is GUI-only — a terminal sends plain SPC for it — so the
  ;; scroll family also needs a TUI-reachable key: C-SPC arrives
  ;; distinctly on a console (as C-@). DEL covers the other direction
  ;; everywhere already.
  (define-key magit-mode-map (kbd "C-SPC") #'magit-diff-show-or-scroll-up)
  (define-key magit-diff-mode-map (kbd "C-SPC") #'scroll-up)
  (define-key magit-blame-read-only-mode-map (kbd "C-SPC") #'magit-diff-show-or-scroll-up)

  ;; Source access from a diff, scoped to magit buffers and aligned
  ;; with the same chords in pr-review: g f = visit the file at point
  ;; (RET's command, on the leader), g e = dwim ediff for the section.
  (evil-define-key 'motion magit-mode-map
    (kbd "<leader> g f") #'magit-diff-visit-file
    (kbd "<leader> g e") #'magit-ediff-dwim))

(with-eval-after-load 'evil
  (ch/leader-prefix-title "g" "git")
  (evil-global-set-key 'motion (kbd "<leader> g s") #'magit-status)
  (evil-global-set-key 'motion (kbd "<leader> g b") #'magit-blame)
  (evil-global-set-key 'motion (kbd "<leader> g l") #'magit-log-current)
  (evil-global-set-key 'motion (kbd "<leader> g d") #'magit-diff-unstaged))
