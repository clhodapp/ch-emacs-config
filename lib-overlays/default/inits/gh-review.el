;; SPDX-License-Identifier: MIT
;; init gh-review
(declare-function evil-define-key* "evil-core")
(declare-function evil-set-initial-state "evil-core")
(declare-function gh-review-blob-diff "gh-review-diff")
(declare-function gh-review-blob-next-change "gh-review-diff")
(declare-function gh-review-blob-other-side "gh-review-diff")
(declare-function gh-review-blob-previous-change "gh-review-diff")
(declare-function gh-review-browse "gh-review-conversation")
(declare-function gh-review-comment "gh-review-diff")
(declare-function gh-review-conversation-visit "gh-review-conversation")
(declare-function gh-review-delete-draft "gh-review-diff")
(declare-function gh-review-editor-cancel "gh-review-diff")
(declare-function gh-review-editor-finish "gh-review-diff")
(declare-function gh-review-ediff "gh-review-diff")
(declare-function gh-review-expand-file "gh-review-diff")
(declare-function gh-review-expand-less "gh-review-diff")
(declare-function gh-review-expand-more "gh-review-diff")
(declare-function gh-review-file-diff "gh-review-diff")
(declare-function gh-review-merge-pr "gh-review-conversation")
(declare-function gh-review-next-change "gh-review-diff")
(declare-function gh-review-next-file "gh-review-diff")
(declare-function gh-review-post-conversation-comment "gh-review-conversation")
(declare-function gh-review-previous-change "gh-review-diff")
(declare-function gh-review-previous-file "gh-review-diff")
(declare-function gh-review-refresh "gh-review-diff")
(declare-function gh-review-reply "gh-review-diff")
(declare-function gh-review-show-after "gh-review-diff")
(declare-function gh-review-show-before "gh-review-diff")
(declare-function gh-review-submit "gh-review-conversation")
(declare-function gh-review-toggle "gh-review-diff")
(declare-function gh-review-toggle-all "gh-review-diff")
(declare-function gh-review-toggle-resolved "gh-review-diff")
(declare-function gh-review-toggle-viewed "gh-review-diff")
(declare-function gh-review-tree-after "gh-review-tree")
(declare-function gh-review-tree-before "gh-review-tree")
(declare-function gh-review-tree-diff "gh-review-tree")
(declare-function gh-review-tree-ediff "gh-review-tree")
(declare-function gh-review-tree-refresh "gh-review-tree")
(declare-function gh-review-tree-toggle "gh-review-tree")
(declare-function gh-review-tree-toggle-all "gh-review-tree")
(declare-function gh-review-visit "gh-review-diff")
(defvar gh-review-diff-mode-map)
(defvar gh-review-conversation-mode-map)
(defvar gh-review-editor-mode-map)
(defvar gh-review-blob-mode-map)
(defvar gh-review-tree-key-map)

(use-package gh-review
  :commands
  (gh-review
   gh-review-dwim
   gh-review-open
   gh-review-dispatch)

  :custom
  ;; Comments and review bodies are GitHub markdown.
  (gh-review-draft-major-mode
   (lambda ()
     (if (fboundp 'markdown-ts-mode) (markdown-ts-mode) (text-mode))))

  :config
  ;; Motion state keeps j/k, search and the SPC leader; the review
  ;; keys below sit in each mode's evil auxiliary map, above motion
  ;; state's own bindings of the same letters.
  (with-eval-after-load 'evil
    (evil-set-initial-state 'gh-review-diff-mode 'motion)
    (evil-set-initial-state 'gh-review-conversation-mode 'motion)
    (evil-define-key 'motion gh-review-diff-mode-map
      (kbd "RET") #'gh-review-visit
      (kbd "TAB") #'gh-review-toggle
      (kbd "<backtab>") #'gh-review-toggle-all
      "za" #'gh-review-toggle
      "]]" #'gh-review-next-file
      "[[" #'gh-review-previous-file
      "]c" #'gh-review-next-change
      "[c" #'gh-review-previous-change
      "o" #'gh-review-show-before
      "a" #'gh-review-show-after
      "d" #'gh-review-file-diff
      "=" #'gh-review-ediff
      "+" #'gh-review-expand-more
      "-" #'gh-review-expand-less
      "E" #'gh-review-expand-file
      "m" #'gh-review-toggle-viewed
      "c" #'gh-review-comment
      "x" #'gh-review-delete-draft
      "r" #'gh-review-reply
      "R" #'gh-review-toggle-resolved
      "gr" #'gh-review-refresh
      "?" #'gh-review-dispatch
      "q" #'quit-window
      (kbd "<leader> g t") #'gh-review-tree-toggle
      (kbd "<leader> g f") #'gh-review-show-after
      (kbd "<leader> g e") #'gh-review-ediff)
    ;; A region of lines becomes one multi-line comment.
    (evil-define-key 'visual gh-review-diff-mode-map
      "c" #'gh-review-comment)
    (evil-define-key 'motion gh-review-conversation-mode-map
      (kbd "RET") #'gh-review-conversation-visit
      "c" #'gh-review-post-conversation-comment
      "S" #'gh-review-submit
      "M" #'gh-review-merge-pr
      "gb" #'gh-review-browse
      "gr" #'gh-review-refresh
      "?" #'gh-review-dispatch
      "q" #'quit-window
      (kbd "<leader> g t") #'gh-review-tree-toggle)
    (evil-define-key 'normal gh-review-editor-mode-map
      "ZZ" #'gh-review-editor-finish
      "ZQ" #'gh-review-editor-cancel)
    (evil-define-key 'motion gh-review-blob-mode-map
      "]c" #'gh-review-blob-next-change
      "[c" #'gh-review-blob-previous-change
      "go" #'gh-review-blob-other-side
      "gd" #'gh-review-blob-diff)))

;; The speedbar tree's keys: speedbar buffers are in normal state, whose
;; b/a/d/e/A would otherwise win over the display's own keymap.
(with-eval-after-load 'gh-review-tree
  (with-eval-after-load 'evil
    (evil-define-key 'normal gh-review-tree-key-map
      "b" #'gh-review-tree-before
      "a" #'gh-review-tree-after
      "d" #'gh-review-tree-diff
      "e" #'gh-review-tree-ediff
      "A" #'gh-review-tree-toggle-all
      "gr" #'gh-review-tree-refresh)))

;; g v reviews the pull request whose link is on the clipboard (or in
;; the region, the kill ring, or at point); g V asks for one.
(with-eval-after-load 'evil
  (ch/leader-prefix-title "g" "git")
  (evil-global-set-key 'motion (kbd "<leader> g v") #'gh-review-dwim)
  (evil-global-set-key 'motion (kbd "<leader> g V") #'gh-review))
