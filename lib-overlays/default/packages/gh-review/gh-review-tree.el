;;; gh-review-tree.el --- The speedbar file tree of gh-review -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; A speedbar display listing the files of one pull request.  It shows
;; the changed files by default, each with its status letter and line
;; counts; toggling it lists every file of the head commit, with the
;; changed ones marked and the directories holding them open.  From a
;; file line the diff, the file before, the file after and an ediff
;; of the two are one key away.
;;
;; The display is registered with `speedbar-add-expansion-list' and
;; pinned to the pull request it was opened for, so it stays put while
;; other buffers are visited.

;;; Code:

(require 'gh-review-core)
(require 'gh-review-diff)
(require 'speedbar)

(defgroup gh-review-tree nil
  "The speedbar file tree of gh-review."
  :group 'gh-review)

(defcustom gh-review-tree-display-function #'gh-review-tree-show
  "Function of a pull request that shows its file tree.
The default opens speedbar's side window.  A configuration that
manages the speedbar window itself replaces it."
  :type 'function)

(defface gh-review-tree-unchanged
  '((t :inherit shadow))
  "Face of a file the pull request leaves unchanged."
  :group 'gh-review-tree)

(defconst gh-review-tree-display-name "Pull Request"
  "Name of the speedbar display.")

(defvar gh-review-tree--pr nil
  "The pull request the tree shows.")

(defvar gh-review-tree-show-all nil
  "Whether the tree lists every file rather than the changed ones.")

(defvar gh-review-tree--menu nil
  "Extra Displays-menu items of the tree (none).")

(defvar gh-review-tree-key-map
  (let ((map (speedbar-make-specialized-keymap)))
    (keymap-set map "b" #'gh-review-tree-before)
    (keymap-set map "a" #'gh-review-tree-after)
    (keymap-set map "d" #'gh-review-tree-diff)
    (keymap-set map "e" #'gh-review-tree-ediff)
    (keymap-set map "A" #'gh-review-tree-toggle-all)
    (keymap-set map "g" #'gh-review-tree-refresh)
    map)
  "Keymap of the tree.")

(defun gh-review-tree--register ()
  "Register the tree as a speedbar display."
  (unless (assoc gh-review-tree-display-name speedbar-initial-expansion-mode-alist)
    (speedbar-add-expansion-list
     (list gh-review-tree-display-name 'gh-review-tree--menu
           'gh-review-tree-key-map #'gh-review-tree--buttons))))

;;; Building the tree

(defun gh-review-tree-nodes (entries)
  "Group ENTRIES, a list of (PARTS . PATH), into tree nodes.
Return (dir NAME CHILDREN) and (file NAME PATH) nodes, directories
first.  A directory holding nothing but one subdirectory merges
with it into a single \"parent/child\" node."
  (let (files groups)
    (dolist (entry entries)
      (let ((parts (car entry))
            (path (cdr entry)))
        (if (null (cdr parts))
            (push (list 'file (car parts) path) files)
          (let ((group (assoc (car parts) groups)))
            (unless group
              (setq group (list (car parts)))
              (push group groups))
            (push (cons (cdr parts) path) (cdr group))))))
    (nconc
     (mapcar (lambda (group)
               (let ((name (car group))
                     (children (gh-review-tree-nodes (nreverse (cdr group)))))
                 (while (and (null (cdr children))
                             (eq (caar children) 'dir))
                   (setq name (concat name "/" (nth 1 (car children)))
                         children (nth 2 (car children))))
                 (list 'dir name children)))
             (nreverse groups))
     (nreverse files))))

(defun gh-review-tree--paths (pr)
  "The paths the tree of PR lists."
  (if gh-review-tree-show-all
      (gh-review-all-paths pr)
    (sort (mapcar #'gh-review-file-path (gh-review-pr-files pr)) #'string<)))

(defun gh-review-tree--has-change-p (nodes pr)
  "Whether NODES hold a file PR changes."
  (seq-some (lambda (node)
              (pcase node
                (`(dir ,_ ,children) (gh-review-tree--has-change-p children pr))
                (`(file ,_ ,path) (gh-review-pr-file pr path))))
            nodes))

;;; Rendering

(defun gh-review-tree--decorate (pr path)
  "Mark the file line just inserted for PATH of PR.
The `>' marker speedbar puts on the line shows the status letter of
a changed file, and the line ends with its counts."
  (save-excursion
    (forward-line -1)
    (let ((file (gh-review-pr-file pr path)))
      (when (re-search-forward "^[0-9]+: *\\(>\\)" (line-end-position) t)
        (speedbar-with-writable
          (put-text-property (match-beginning 1) (match-end 1) 'display
                             (if file (gh-review--status-marker file) " "))))
      (speedbar-with-writable
        (end-of-line)
        (if file
            (insert " "
                    (propertize (format "+%d" (gh-review-file-additions file))
                                'face 'gh-review-status-added)
                    " "
                    (propertize (format "−%d" (gh-review-file-deletions file))
                                'face 'gh-review-status-deleted))
          (beginning-of-line)
          (when (re-search-forward "> \\(.*\\)$" (line-end-position) t)
            (add-face-text-property (match-beginning 1) (match-end 1)
                                    'gh-review-tree-unchanged)))))))

(defun gh-review-tree--insert-nodes (nodes pr depth)
  "Insert tag lines for NODES of PR's tree at DEPTH."
  (dolist (node nodes)
    (pcase-exhaustive node
      (`(dir ,name ,children)
       (let ((open (or (not gh-review-tree-show-all)
                       (gh-review-tree--has-change-p children pr))))
         (speedbar-make-tag-line 'curly (if open ?- ?+)
                                 #'gh-review-tree--expand (cons children pr)
                                 name nil nil 'speedbar-directory-face depth)
         (when open
           (gh-review-tree--insert-nodes children pr (1+ depth)))))
      (`(file ,name ,path)
       (speedbar-make-tag-line nil nil nil nil
                               name #'gh-review-tree--visit path
                               'speedbar-file-face depth)
       (gh-review-tree--decorate pr path)))))

(defun gh-review-tree--expand (text token indent)
  "Expand or contract a directory line (speedbar button contract).
TEXT is the button's text, TOKEN is (CHILDREN . PR), INDENT the
line's depth."
  (cond
   ((string-search "+" text)
    (speedbar-change-expand-button-char ?-)
    (speedbar-with-writable
      (save-excursion
        (end-of-line)
        (forward-char 1)
        (gh-review-tree--insert-nodes (car token) (cdr token) (1+ indent)))))
   ((string-search "-" text)
    (speedbar-change-expand-button-char ?+)
    (speedbar-delete-subblock indent))))

(defun gh-review-tree--buttons (_directory _depth)
  "Fill the speedbar with the tree of `gh-review-tree--pr'."
  (let ((pr gh-review-tree--pr))
    (erase-buffer)
    (if (not (and pr (eq (gh-review-pr-status pr) 'ready)))
        (insert (propertize "No pull request loaded\n" 'face 'gh-review-meta))
      (insert (propertize (gh-review-pr-key pr) 'face 'speedbar-directory-face)
              (propertize (if gh-review-tree-show-all "  all files" "  changed files")
                          'face 'gh-review-meta)
              "\n")
      (gh-review-tree--insert-nodes
       (gh-review-tree-nodes
        (mapcar (lambda (path) (cons (split-string path "/") path))
                (gh-review-tree--paths pr)))
       pr 0))))

;;; Showing the tree

(defun gh-review-tree-fill (pr)
  "Show PR's tree in the speedbar buffer, which must exist."
  (gh-review-tree--register)
  (setq gh-review-tree--pr pr)
  (with-current-buffer speedbar-buffer
    (setq speedbar-full-text-cache nil)
    (speedbar-change-initial-expansion-list gh-review-tree-display-name)
    (speedbar-refresh)))

(defun gh-review-tree-show (pr)
  "Open speedbar's side window on PR's tree."
  (setq speedbar-update-flag nil)
  (speedbar-window-mode 1)
  ;; Emacs 31.1's `speedbar-window-mode' leaves its buffer outside
  ;; `speedbar-mode', which owns the keymap and the button handling.
  (with-current-buffer speedbar-buffer
    (unless (derived-mode-p 'speedbar-mode)
      (speedbar-mode)))
  (gh-review-tree-fill pr))

(defun gh-review-tree--shown-p ()
  "Whether the speedbar window is up and showing a tree."
  (and (boundp 'speedbar-buffer) (buffer-live-p speedbar-buffer)
       (get-buffer-window speedbar-buffer)
       (equal (buffer-local-value 'speedbar-initial-expansion-list-name
                                  speedbar-buffer)
              gh-review-tree-display-name)))

;;;###autoload
(defun gh-review-tree-toggle ()
  "Show the current pull request's file tree, or hide it."
  (interactive)
  (let ((pr (gh-review-current-pr)))
    (if (and (gh-review-tree--shown-p) (eq gh-review-tree--pr pr))
        (speedbar-window-mode -1)
      (funcall gh-review-tree-display-function pr))))

(defun gh-review-tree-refresh-for (pr)
  "Redraw the tree when it shows PR."
  (when (and (eq gh-review-tree--pr pr) (gh-review-tree--shown-p))
    (gh-review-tree-fill pr)))

(add-hook 'gh-review-refresh-hook #'gh-review-tree-refresh-for)

(defun gh-review-tree-follow (path)
  "Move the tree's point to PATH's line when the tree is showing."
  (when-let* (((gh-review-tree--shown-p))
              (window (get-buffer-window speedbar-buffer)))
    (with-current-buffer speedbar-buffer
      (save-excursion
        (goto-char (point-min))
        (when-let* ((match (text-property-search-forward
                            'speedbar-token path #'equal)))
          (set-window-point window (prop-match-beginning match)))))))

;;; Commands on tree lines

(defun gh-review-tree--path-at-point ()
  "The path of the file line at point, or a user error."
  (let ((token (speedbar-line-token)))
    (if (stringp token) token (user-error "Not on a file"))))

(defun gh-review-tree--main-window (pr)
  "A window of PR's diff buffer in this frame, or the most recent other."
  (or (get-buffer-window (gh-review-diff-buffer pr))
      (get-mru-window nil nil t)))

(defun gh-review-tree--visit (_text path _indent)
  "Go to PATH from its tree line: its diff when changed, else the file."
  (let ((pr gh-review-tree--pr))
    (select-window (gh-review-tree--main-window pr))
    (if (gh-review-pr-file pr path)
        (progn
          (switch-to-buffer (gh-review-diff-buffer pr))
          (gh-review-goto-file path))
      (gh-review-show-side pr path 'after))))

(defmacro gh-review-tree--from-main (&rest body)
  "Run BODY in the diff buffer's window of the tree's pull request."
  (declare (indent 0))
  `(let ((path (gh-review-tree--path-at-point))
         (pr gh-review-tree--pr))
     (select-window (gh-review-tree--main-window pr))
     (with-current-buffer (gh-review-diff-buffer pr)
       ,@body)))

(defun gh-review-tree-before ()
  "Show the file at point as it was at the merge base."
  (interactive)
  (gh-review-tree--from-main
    (let ((file (gh-review-pr-file pr path)))
      (gh-review-show-side pr (if file (gh-review-file-old-path file) path)
                           'before))))

(defun gh-review-tree-after ()
  "Show the file at point as it is at the head."
  (interactive)
  (gh-review-tree--from-main (gh-review-show-side pr path 'after)))

(defun gh-review-tree-diff ()
  "Show the whole-file diff of the file at point."
  (interactive)
  (gh-review-tree--from-main (gh-review-file-diff path)))

(defun gh-review-tree-ediff ()
  "Compare the file at point before and after with ediff."
  (interactive)
  (gh-review-tree--from-main
    (let ((file (or (gh-review-pr-file pr path)
                    (user-error "%s is unchanged" path))))
      (when (memq (gh-review-file-status file) '(added deleted))
        (user-error "%s exists on one side only" path))
      (ediff-buffers (gh-review--blob-buffer pr (gh-review-file-old-path file) 'before)
                     (gh-review--blob-buffer pr path 'after)))))

(defun gh-review-tree-toggle-all ()
  "Switch the tree between changed files and every file."
  (interactive)
  (setq gh-review-tree-show-all (not gh-review-tree-show-all))
  (gh-review-tree-fill gh-review-tree--pr))

(defun gh-review-tree-refresh ()
  "Redraw the tree."
  (interactive)
  (gh-review-tree-fill gh-review-tree--pr))

(provide 'gh-review-tree)
;;; gh-review-tree.el ends here
