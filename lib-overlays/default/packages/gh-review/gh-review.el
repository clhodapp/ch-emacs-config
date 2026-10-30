;;; gh-review.el --- Review GitHub pull requests -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;; Package-Requires: ((emacs "31.1"))
;; Keywords: tools, vc

;;; Commentary:

;; gh-review opens a GitHub pull request in its own tab, laid out
;; like GitHub's review page: the file tree on the left (a speedbar
;; display), the diff in the middle, the conversation on the right.
;;
;; `gh-review-dwim' opens the pull request whose link is in the
;; region, on the clipboard, at the head of the kill ring or at point,
;; without prompting; `gh-review' asks for a link or OWNER/REPO#N.
;; `gh-review-dispatch' lists every command of a review buffer.
;;
;; Everything is read through the `gh' CLI and a cache repository
;; holding the pull request's two commits; see gh-review-core.el.

;;; Code:

(require 'gh-review-core)
(require 'gh-review-diff)
(require 'gh-review-tree)
(require 'gh-review-conversation)
(require 'transient)

(defcustom gh-review-use-tab t
  "Whether each pull request opens in a tab of its own."
  :type 'boolean
  :group 'gh-review)

(defvar gh-review-layout-hook nil
  "Hook run with the pull request once its layout is up.
The diff window is selected while it runs.")

;;; Finding a reference

(defun gh-review--clipboard ()
  "The clipboard's text, or nil when there is none or no display."
  (ignore-errors
    (let ((text (gui-get-selection 'CLIPBOARD 'UTF8_STRING)))
      (and (stringp text) (substring-no-properties text)))))

(defun gh-review--candidate-texts ()
  "Texts that may hold a pull request reference, most specific first."
  (delq nil
        (list (and (use-region-p)
                   (buffer-substring-no-properties (region-beginning) (region-end)))
              (gh-review--clipboard)
              (ignore-errors (current-kill 0 t))
              (thing-at-point 'url t)
              (thing-at-point 'line t))))

(defun gh-review-reference-dwim ()
  "The first pull request reference found where `gh-review-dwim' looks."
  (seq-some #'gh-review-parse-reference (gh-review--candidate-texts)))

(defun gh-review--read-reference ()
  "Ask for a pull request reference, offering the one found nearby."
  (let* ((found (gh-review-reference-dwim))
         (default (and found (apply #'format "%s/%s#%d" found)))
         (input (read-string (format-prompt "Pull request (URL or OWNER/REPO#N)"
                                            default)
                             nil nil default)))
    (or (gh-review-parse-reference input)
        (user-error "Not a pull request reference: %s" input))))

;;; Opening

(defun gh-review--tab-name (pr)
  "Name of PR's tab."
  (format "PR %s" (gh-review-pr-key pr)))

(defun gh-review--select-tab (pr)
  "Switch to PR's tab, creating it when missing.
Return non-nil when the tab already existed."
  (let ((name (gh-review--tab-name pr)))
    (if (tab-bar--tab-index-by-name name)
        (progn (tab-bar-switch-to-tab name) t)
      (tab-bar-new-tab)
      (tab-bar-rename-tab name)
      nil)))

(defun gh-review-display-layout (pr)
  "Lay PR's buffers out in the selected frame."
  (delete-other-windows)
  (switch-to-buffer (gh-review-diff-buffer pr))
  (display-buffer-in-side-window
   (gh-review-conversation-buffer pr)
   `((side . right) (slot . 0) (window-width . ,gh-review-conversation-width)
     (preserve-size . (t . nil))
     (window-parameters . ((no-delete-other-windows . t)))))
  (when (eq (gh-review-pr-status pr) 'ready)
    (ignore-errors (funcall gh-review-tree-display-function pr)))
  (select-window (get-buffer-window (gh-review-diff-buffer pr)))
  (run-hook-with-args 'gh-review-layout-hook pr))

(defun gh-review--show-tree-once-loaded (pr)
  "Show PR's tree when the load that opened it finishes."
  (when (and (eq (gh-review-pr-status pr) 'ready)
             (get-buffer-window (gh-review-diff-buffer pr)))
    (with-selected-window (get-buffer-window (gh-review-diff-buffer pr))
      (ignore-errors (funcall gh-review-tree-display-function pr)))))

;;;###autoload
(defun gh-review-open (owner repo number)
  "Open the review of pull request NUMBER of OWNER/REPO."
  (let* ((pr (gh-review-pr-for owner repo number))
         (existed (and gh-review-use-tab (gh-review--select-tab pr))))
    (unless existed
      (gh-review-display-layout pr))
    (when (memq (gh-review-pr-status pr) '(new error))
      (gh-review-load pr #'gh-review--show-tree-once-loaded))
    pr))

;;;###autoload
(defun gh-review (reference)
  "Open the review of the pull request REFERENCE.
REFERENCE is a pull request URL or OWNER/REPO#NUMBER; interactively
the one in the region, on the clipboard or at point is offered."
  (interactive (list (gh-review--read-reference)))
  (apply #'gh-review-open
         (if (stringp reference) (gh-review-parse-reference reference) reference)))

;;;###autoload
(defun gh-review-dwim ()
  "Open the pull request linked in the region, clipboard, kill ring or point.
Ask only when none of them holds a pull request reference."
  (interactive)
  (if-let* ((reference (gh-review-reference-dwim)))
      (apply #'gh-review-open reference)
    (call-interactively #'gh-review)))

(defun gh-review-quit ()
  "Close the current pull request's buffers and its tab."
  (interactive)
  (let* ((pr (gh-review-current-pr))
         (name (gh-review--tab-name pr)))
    (dolist (buffer (buffer-list))
      (when (eq (buffer-local-value 'gh-review-buffer-pr buffer) pr)
        (kill-buffer buffer)))
    (when (and gh-review-use-tab (tab-bar--tab-index-by-name name))
      (tab-bar-close-tab-by-name name))))

(defun gh-review-relayout ()
  "Restore the current pull request's window layout."
  (interactive)
  (gh-review-display-layout (gh-review-current-pr)))

;;; The command menu

;;;###autoload (autoload 'gh-review-dispatch "gh-review" nil t)
(transient-define-prefix gh-review-dispatch ()
  "Commands of a pull request review."
  [["Files"
    ("RET" "Visit or expand at point" gh-review-visit)
    ("TAB" "Fold file or thread" gh-review-toggle)
    ("o" "File before" gh-review-show-before)
    ("a" "File after" gh-review-show-after)
    ("d" "Whole-file diff" gh-review-file-diff)
    ("=" "Ediff before and after" gh-review-ediff)
    ("t" "File tree" gh-review-tree-toggle)]
   ["Context"
    ("+" "Expand hidden lines" gh-review-expand-more)
    ("E" "Expand whole file" gh-review-expand-file)
    ("-" "Collapse context" gh-review-expand-less)
    ("m" "Toggle viewed" gh-review-toggle-viewed)]
   ["Review"
    ("c" "Comment on line or region" gh-review-comment)
    ("x" "Delete pending comment" gh-review-delete-draft)
    ("r" "Reply to thread" gh-review-reply)
    ("R" "Resolve or unresolve thread" gh-review-toggle-resolved)
    ("S" "Submit review" gh-review-submit)
    ("A" "Approve" gh-review-approve)]
   ["Pull request"
    ("C" "Comment on conversation" gh-review-post-conversation-comment)
    ("M" "Merge" gh-review-merge-pr)
    ("b" "Open on GitHub" gh-review-browse)
    ("g" "Refresh" gh-review-refresh)
    ("L" "Restore layout" gh-review-relayout)
    ("q" "Close review" gh-review-quit)]])

(provide 'gh-review)
;;; gh-review.el ends here
