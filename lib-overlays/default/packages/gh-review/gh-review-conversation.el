;;; gh-review-conversation.el --- The conversation panel of gh-review -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; The conversation panel holds what GitHub shows on a pull request's
;; Conversation tab: the description, the status checks, the comments
;; and reviews in order, and an index of the review threads.  It also
;; holds the commands that publish: submitting a review with the
;; pending comments, posting a comment, and merging.

;;; Code:

(require 'gh-review-core)
(require 'gh-review-diff)
(require 'shr)

(defgroup gh-review-conversation nil
  "The conversation panel of gh-review."
  :group 'gh-review)

(defcustom gh-review-conversation-width 0.32
  "Width of the conversation side window, as a fraction of the frame."
  :type 'number)

(defcustom gh-review-merge-method-preference '(squash merge rebase)
  "Merge methods in order of preference; the first one allowed is the default."
  :type '(repeat (choice (const merge) (const squash) (const rebase))))

(defvar gh-review-conversation-sections-functions nil
  "Functions inserting extra sections into the conversation panel.
Each is called with the pull request, at the end of the buffer.")

(defun gh-review--insert-heading (text)
  "Insert the section heading TEXT."
  (insert "\n" (propertize text 'face '(:inherit bold :height 1.1)) "\n"))

(defvar-local gh-review--rendered-width nil
  "Width the conversation panel was last filled to.")

(defun gh-review--panel-width ()
  "Width to fill the conversation panel's text to.
The panel's own window decides it; before the panel is displayed,
the width it will get in the layout stands in."
  (let ((window (get-buffer-window (current-buffer))))
    (max 30 (- (if window
                   (window-body-width window)
                 (floor (* (frame-width) gh-review-conversation-width)))
               2))))

(defun gh-review--conversation-resized (window)
  "Fill the conversation panel shown in WINDOW again if its width changed."
  (with-current-buffer (window-buffer window)
    (unless (eql gh-review--rendered-width (gh-review--panel-width))
      (gh-review-conversation-render))))

(defun gh-review--insert-html (html fallback)
  "Insert HTML rendered by shr, or FALLBACK text when that fails."
  (if (and html (not (string-empty-p html)) (fboundp 'libxml-parse-html-region))
      (condition-case nil
          (let ((dom (with-temp-buffer
                       (insert html)
                       (libxml-parse-html-region (point-min) (point-max))))
                (shr-width gh-review--rendered-width))
            (shr-insert-document dom)
            (unless (bolp) (insert "\n")))
        (error (insert (or fallback "") "\n")))
    (insert (or fallback "") "\n")))

(defun gh-review--check-glyph (state)
  "A glyph with a face for the check STATE."
  (pcase state
    ((or "SUCCESS" "NEUTRAL" "SKIPPED") (propertize "✓" 'face 'success))
    ((or "FAILURE" "ERROR" "CANCELLED" "TIMED_OUT" "ACTION_REQUIRED" "STARTUP_FAILURE")
     (propertize "✗" 'face 'error))
    (_ (propertize "●" 'face 'warning))))

(defun gh-review--timeline (pr)
  "PR's comments and submitted reviews in date order, as (DATE KIND ITEM)."
  (sort (append
         (mapcar (lambda (c) (list (alist-get 'createdAt c) 'comment c))
                 (gh-review-pr-comments pr))
         (delq nil (mapcar (lambda (r)
                             (when (alist-get 'submittedAt r)
                               (list (alist-get 'submittedAt r) 'review r)))
                           (gh-review-pr-reviews pr))))
        (lambda (a b) (string< (car a) (car b)))))

(defun gh-review-conversation-render ()
  "Redraw the conversation panel from its pull request."
  (let ((pr gh-review-buffer-pr)
        (inhibit-read-only t)
        (position (point)))
    (setq gh-review--rendered-width (gh-review--panel-width))
    (erase-buffer)
    (if (not (eq (gh-review-pr-status pr) 'ready))
        (insert (propertize (if (eq (gh-review-pr-status pr) 'error)
                                (or (gh-review-pr-error pr) "Error")
                              "Loading…")
                            'face 'gh-review-meta)
                "\n")
      (insert (propertize (gh-review-pr-title pr) 'face 'gh-review-title) "\n"
              (propertize (format "%s by %s\n" (gh-review-pr-key pr)
                                  (gh-review-pr-author pr))
                          'face 'gh-review-meta))
      (gh-review--insert-heading "Description")
      (gh-review--insert-html (gh-review-pr-body-html pr)
                              (let ((body (gh-review-pr-body pr)))
                                (if (string-empty-p (or body ""))
                                    "(no description)"
                                  body)))
      (let ((contexts (plist-get (gh-review-pr-checks pr) :contexts)))
        (when contexts
          (gh-review--insert-heading "Checks")
          (dolist (check contexts)
            (insert "  " (gh-review--check-glyph (plist-get check :state)) " ")
            (if (plist-get check :url)
                (insert-text-button (or (plist-get check :name) "?")
                                    'action (let ((url (plist-get check :url)))
                                              (lambda (_) (browse-url url)))
                                    'follow-link t)
              (insert (or (plist-get check :name) "?")))
            (insert (propertize (format "  %s\n" (downcase (or (plist-get check :state) "")))
                                'face 'gh-review-meta)))))
      (let ((timeline (gh-review--timeline pr)))
        (when timeline
          (gh-review--insert-heading "Activity")
          (dolist (entry timeline)
            (pcase-let ((`(,date ,kind ,item) entry))
              (let ((start (point)))
                (insert (propertize (or (gh-review--dig item 'author 'login) "ghost")
                                    'face 'gh-review-thread-author)
                        (propertize
                         (format "  %s %s\n"
                                 (if (eq kind 'review)
                                     (pcase (alist-get 'state item)
                                       ("APPROVED" "approved")
                                       ("CHANGES_REQUESTED" "requested changes")
                                       ("DISMISSED" "reviewed (dismissed)")
                                       (_ "reviewed"))
                                   "commented")
                                 (gh-review--date date))
                         'face 'gh-review-meta))
                (unless (string-empty-p (or (alist-get 'body item) ""))
                  (gh-review--insert-html (alist-get 'bodyHTML item)
                                          (alist-get 'body item)))
                (put-text-property start (point) 'gh-review-timeline item))))))
      (let ((threads (gh-review-pr-threads pr)))
        (when threads
          (gh-review--insert-heading
           (format "Review threads (%d open)"
                   (seq-count (lambda (thread) (not (alist-get 'isResolved thread)))
                              threads)))
          (dolist (thread threads)
            (let* ((comments (gh-review--nodes thread 'comments))
                   (first (car comments))
                   (start (point)))
              (insert (if (alist-get 'isResolved thread)
                          (propertize "  ✓ " 'face 'success)
                        "  ● ")
                      (propertize (format "%s:%s" (alist-get 'path thread)
                                          (or (alist-get 'line thread)
                                              (alist-get 'originalLine thread)))
                                  'face 'gh-review-file-path)
                      (if (alist-get 'isOutdated thread)
                          (propertize " (outdated)" 'face 'gh-review-meta)
                        "")
                      "  "
                      (propertize (or (gh-review--dig first 'author 'login) "")
                                  'face 'gh-review-thread-author)
                      ": "
                      (truncate-string-to-width
                       (car (gh-review--body-lines (alist-get 'body first)))
                       60 nil nil "…")
                      (if (cdr comments)
                          (propertize (format "  +%d" (length (cdr comments)))
                                      'face 'gh-review-meta)
                        "")
                      "\n")
              (put-text-property start (point) 'gh-review-thread thread)))))
      (gh-review--insert-heading "Your review")
      (let ((drafts (gh-review-pr-drafts pr)))
        (insert (if drafts
                    (format "  %d pending comment%s.  "
                            (length drafts) (if (cdr drafts) "s" ""))
                  "  No pending comments.  "))
        (insert-text-button "Submit review"
                            'action (lambda (_) (gh-review-submit))
                            'follow-link t)
        (when (and (not (gh-review-pr-viewer-authored-p pr))
                   (equal (gh-review-pr-state pr) "OPEN"))
          (insert "  ")
          (insert-text-button "Approve"
                              'action (lambda (_) (gh-review-approve))
                              'follow-link t))
        (when (equal (gh-review-pr-state pr) "OPEN")
          (insert "  ")
          (insert-text-button "Merge"
                              'action (lambda (_) (gh-review-merge-pr))
                              'follow-link t))
        (insert "\n"))
      (run-hook-with-args 'gh-review-conversation-sections-functions pr))
    (goto-char (min position (point-max)))))

(defvar-keymap gh-review-conversation-mode-map
  :doc "Keymap of `gh-review-conversation-mode'."
  :parent special-mode-map
  "RET" #'gh-review-conversation-visit
  "c" #'gh-review-post-conversation-comment
  "S" #'gh-review-submit
  "M" #'gh-review-merge-pr
  "b" #'gh-review-browse
  "g" #'gh-review-refresh)

(define-derived-mode gh-review-conversation-mode special-mode "PR Conversation"
  "Major mode of a pull request's conversation panel.

\\{gh-review-conversation-mode-map}"
  :interactive nil
  (setq buffer-read-only t)
  (setq-local revert-buffer-function (lambda (&rest _) (gh-review-refresh)))
  (add-hook 'window-size-change-functions #'gh-review--conversation-resized nil t)
  (visual-line-mode 1))

(defun gh-review-conversation-buffer (pr)
  "The conversation panel of PR, created when missing."
  (let ((name (format "*%s conversation*" (gh-review-pr-key pr))))
    (or (get-buffer name)
        (with-current-buffer (get-buffer-create name)
          (gh-review-conversation-mode)
          (setq gh-review-buffer-pr pr)
          (gh-review-conversation-render)
          (current-buffer)))))

(defun gh-review-conversation-visit ()
  "Go to the diff line of the review thread at point."
  (interactive)
  (let* ((pr (gh-review-current-pr))
         (thread (or (get-text-property (point) 'gh-review-thread)
                     (user-error "Not on a review thread")))
         (buffer (gh-review-diff-buffer pr)))
    (pop-to-buffer buffer '((display-buffer-reuse-window
                             display-buffer-use-some-window)
                            (inhibit-same-window . t)))
    (gh-review-goto-file (alist-get 'path thread))
    (when-let* ((line (alist-get 'line thread)))
      (gh-review--restore-position
       (list 'line (alist-get 'path thread) (alist-get 'diffSide thread) line)))))

(defun gh-review-browse ()
  "Open the pull request on GitHub."
  (interactive)
  (browse-url (gh-review-pr-url (gh-review-current-pr))))

;;; Publishing

(defun gh-review-post-conversation-comment ()
  "Write a comment on the pull request's conversation and post it."
  (interactive)
  (let ((pr (gh-review-current-pr)))
    (gh-review-edit-text
     (format "comment on %s" (gh-review-pr-key pr)) nil
     (lambda (body)
       (unless (string-empty-p body)
         (gh-review-post-comment pr body
                                 (lambda (_)
                                   (message "Comment posted")
                                   (gh-review-load pr)))))
     pr)))

(defun gh-review--review-events (pr)
  "The review events available on PR, as (LABEL . EVENT) pairs.
GitHub accepts only comment reviews on a pull request its author
reviews."
  (if (gh-review-pr-viewer-authored-p pr)
      '(("Comment" . "COMMENT"))
    '(("Approve" . "APPROVE")
      ("Request changes" . "REQUEST_CHANGES")
      ("Comment" . "COMMENT"))))

(defun gh-review--draft-comments (pr)
  "PR's pending comments in the shape `gh-review-submit-review' takes."
  (mapcar (lambda (draft)
            (list :path (plist-get draft :path)
                  :line (plist-get draft :line)
                  :side (plist-get draft :side)
                  :start-line (plist-get draft :start-line)
                  :start-side (plist-get draft :start-side)
                  :body (plist-get draft :body)))
          (gh-review-pr-drafts pr)))

(defun gh-review-compose-review (pr event &optional body)
  "Write the body of a review of PR with EVENT, then submit it.
EVENT is \"APPROVE\", \"REQUEST_CHANGES\" or \"COMMENT\"; BODY is the
starting text.  The pending comments go with the review and are
cleared once GitHub accepted it."
  (gh-review-edit-text
   (format "%s review of %s"
           (car (rassoc event (gh-review--review-events pr)))
           (gh-review-pr-key pr))
   body
   (lambda (text)
     (let ((comments (gh-review--draft-comments pr)))
       (when (and (not (equal event "APPROVE"))
                  (string-empty-p text) (null comments))
         (user-error "A review needs a body or a pending comment"))
       (gh-review-submit-review
        pr event text comments
        (lambda (_)
          (setf (gh-review-pr-drafts pr) nil)
          (gh-review-save-drafts pr)
          (message "Review submitted on %s" (gh-review-pr-key pr))
          (gh-review-load pr)))))
   pr))

(defun gh-review-submit ()
  "Submit a review of the current pull request with the pending comments."
  (interactive)
  (let* ((pr (gh-review-current-pr))
         (events (gh-review--review-events pr))
         (choice (completing-read "Review: " events nil t nil nil (caar events))))
    (gh-review-compose-review pr (cdr (assoc choice events)))))

(defun gh-review-approve ()
  "Approve the current pull request, with the pending comments."
  (interactive)
  (let ((pr (gh-review-current-pr)))
    (when (gh-review-pr-viewer-authored-p pr)
      (user-error "GitHub does not let the author approve a pull request"))
    (gh-review-compose-review pr "APPROVE")))

(defun gh-review-merge-pr ()
  "Merge the current pull request, after asking for the method."
  (interactive)
  (let* ((pr (gh-review-current-pr))
         (allowed (gh-review-pr-merge-methods pr))
         (default (seq-find (lambda (m) (memq m allowed))
                            gh-review-merge-method-preference))
         (method (intern (completing-read
                          (format "Merge %s by: " (gh-review-pr-key pr))
                          (mapcar #'symbol-name allowed) nil t nil nil
                          (and default (symbol-name default))))))
    (when (yes-or-no-p (format "Merge %s (%s) into %s by %s? "
                               (gh-review-pr-key pr) (gh-review-pr-title pr)
                               (gh-review-pr-base-ref pr) method))
      (gh-review-merge pr method
                       (lambda ()
                         (message "Merged %s" (gh-review-pr-key pr))
                         (gh-review-load pr))))))

(provide 'gh-review-conversation)
;;; gh-review-conversation.el ends here
