;;; gh-review-diff.el --- The diff buffer of gh-review -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; The diff buffer shows a pull request the way GitHub's "Files
;; changed" tab does: one card per file, a header band naming the file
;; with its status and counts, a gutter of old and new line numbers,
;; and rows standing in for the unchanged lines between changes.  A
;; hidden-lines row expands upward, downward or completely, so the
;; surrounding file can be read without leaving the diff.  Review
;; threads, pending comments and annotations from other packages are
;; drawn under the line they belong to.
;;
;; The diff is computed with no context lines; every unchanged line
;; shown comes from the file contents, so any amount of context costs
;; nothing extra to fetch.  Each file card is rendered on its own,
;; which keeps expanding one file from redrawing the others.

;;; Code:

(require 'gh-review-core)
(require 'text-property-search)

(declare-function gh-review-tree-follow "gh-review-tree")

;;; Options

(defgroup gh-review-diff nil
  "The diff buffer of gh-review."
  :group 'gh-review)

(defcustom gh-review-context-lines 3
  "Unchanged lines shown on each side of a change before expanding."
  :type 'natnum)

(defcustom gh-review-expand-step 20
  "Lines one expansion of a hidden-lines row reveals."
  :type 'natnum)

(defcustom gh-review-fontify t
  "Whether diff lines get the syntax highlighting of their file's mode."
  :type 'boolean)

(defcustom gh-review-fontify-max-size 300000
  "Files larger than this many characters are not syntax highlighted."
  :type 'natnum)

(defcustom gh-review-collapse-file-regexps
  '("\\.lock\\'" "\\(?:\\`\\|/\\)package-lock\\.json\\'" "\\.min\\.\\(?:js\\|css\\)\\'")
  "Files matching one of these regexps start collapsed."
  :type '(repeat regexp))

(defcustom gh-review-collapse-file-lines 600
  "Files with more changed lines than this start collapsed."
  :type 'natnum)

(defcustom gh-review-draft-major-mode #'text-mode
  "Major mode of the buffers comments and review bodies are written in."
  :type 'function)

(defvar gh-review-annotation-functions nil
  "Functions returning annotations to draw in the diff.
Each is called with the pull request and returns a list of plists
with :heading and :body strings, :face, and the anchor: :path, :side
\(\"LEFT\" or \"RIGHT\") and :line.  An annotation with a path and
no line is drawn under the file header, one without a path at the
top of the buffer.  Other keys are kept and can be read back with
`gh-review-annotation-at-point'.")

;;; Faces

(defgroup gh-review-faces nil
  "Faces of gh-review."
  :group 'gh-review)

(defface gh-review-title
  '((t :inherit bold :height 1.3))
  "Face of the pull request title.")

(defface gh-review-meta
  '((t :inherit shadow))
  "Face of secondary information.")

(defface gh-review-file-header
  '((((class color) (background dark))
     :background "#21262d" :overline "#3d444d" :extend t)
    (((class color) (background light))
     :background "#f6f8fa" :overline "#d1d9e0" :extend t)
    (t :inverse-video t :extend t))
  "Face of a file card's header band.")

(defface gh-review-file-path
  '((t :inherit bold))
  "Face of the path in a file header.")

(defface gh-review-added
  '((((class color) (background dark)) :background "#12261e" :extend t)
    (((class color) (background light)) :background "#e6ffec" :extend t)
    (t :inherit diff-added))
  "Face of an added line.")

(defface gh-review-removed
  '((((class color) (background dark)) :background "#25171c" :extend t)
    (((class color) (background light)) :background "#ffebe9" :extend t)
    (t :inherit diff-removed))
  "Face of a removed line.")

(defface gh-review-added-gutter
  '((((class color) (background dark)) :background "#1b4721" :foreground "#8ddb8c")
    (((class color) (background light)) :background "#ccffd8" :foreground "#1a7f37")
    (t :inherit diff-indicator-added))
  "Face of the line numbers and marker of an added line.")

(defface gh-review-removed-gutter
  '((((class color) (background dark)) :background "#542426" :foreground "#f47067")
    (((class color) (background light)) :background "#ffd7d5" :foreground "#cf222e")
    (t :inherit diff-indicator-removed))
  "Face of the line numbers and marker of a removed line.")

(defface gh-review-gutter
  '((t :inherit line-number))
  "Face of the line numbers of an unchanged line.")

(defface gh-review-gap
  '((((class color) (background dark))
     :background "#121d2f" :foreground "#9198a1" :extend t)
    (((class color) (background light))
     :background "#ddf4ff" :foreground "#59636e" :extend t)
    (t :inherit shadow))
  "Face of a hidden-lines row.")

(defface gh-review-thread
  '((((class color) (background dark)) :background "#161b22" :extend t)
    (((class color) (background light)) :background "#f6f8fa" :extend t)
    (t :inherit default))
  "Face of review thread lines.")

(defface gh-review-thread-author
  '((t :inherit bold))
  "Face of a comment's author.")

(defface gh-review-resolved
  '((t :inherit shadow))
  "Face of a resolved thread's header.")

(defface gh-review-draft
  '((((class color) (background dark)) :background "#272115" :extend t)
    (((class color) (background light)) :background "#fff8c5" :extend t)
    (t :inherit highlight))
  "Face of a pending review comment.")

(defface gh-review-annotation
  '((((class color) (background dark)) :background "#1d1a2e" :extend t)
    (((class color) (background light)) :background "#fbefff" :extend t)
    (t :inherit highlight))
  "Default face of an annotation.")

(defface gh-review-status-added '((t :inherit success))
  "Face of the added status marker.")

(defface gh-review-status-deleted '((t :inherit error))
  "Face of the deleted status marker.")

(defface gh-review-status-modified '((t :inherit warning))
  "Face of the modified status marker.")

(defface gh-review-status-renamed '((t :inherit font-lock-constant-face))
  "Face of the renamed and copied status markers.")

;;; Line plans

(defun gh-review--hunk-bounds (hunk)
  "The first and last new-side line HUNK covers, as a cons.
A hunk adding nothing covers no new line; its bounds are the empty
interval just after its start."
  (let ((start (gh-review-hunk-new-start hunk))
        (count (gh-review-hunk-new-count hunk)))
    (if (zerop count)
        (cons (1+ start) start)
      (cons start (+ start count -1)))))

(defun gh-review--regions (file)
  "The unchanged regions of FILE around its hunks.
Return a list with one plist per region, before the first hunk,
between hunks and after the last: :index, :start and :end in new
line numbers (end below start for an empty region), :delta to add
to a new line number for the old one, and :first and :last saying
whether the region opens or closes the file."
  (let* ((hunks (gh-review-file-hunks file))
         (total (length (gh-review-file-new-lines file)))
         (delta 0) (start 1) (index 0) (regions nil))
    (dolist (hunk hunks)
      (let ((bounds (gh-review--hunk-bounds hunk)))
        (push (list :index index :start start :end (1- (car bounds))
                    :delta delta :first (zerop index) :last nil)
              regions)
        (setq delta (+ delta (- (gh-review-hunk-old-count hunk)
                                (gh-review-hunk-new-count hunk)))
              start (1+ (cdr bounds))
              index (1+ index))))
    (push (list :index index :start start :end total :delta delta
                :first (zerop index) :last t)
          regions)
    (nreverse regions)))

(defun gh-review--region-shown (region gaps)
  "Lines of REGION shown at its top and bottom, as a cons.
GAPS is the file's expansion state, an alist from region index to
`all' or a (TOP . BOTTOM) cons; a region absent from it shows
`gh-review-context-lines' next to each adjacent change.  Return
`all' when everything is shown."
  (let* ((length (1+ (- (plist-get region :end) (plist-get region :start))))
         (state (alist-get (plist-get region :index) gaps))
         (shown (cond ((eq state 'all) nil)
                      (state state)
                      (t (cons (if (plist-get region :first) 0
                                 gh-review-context-lines)
                               (if (plist-get region :last) 0
                                 gh-review-context-lines))))))
    (if (or (null shown)
            ;; A row costs a line, so hiding one or two lines saves
            ;; nothing.
            (<= (- length (car shown) (cdr shown)) 2))
        'all
      shown)))

(defun gh-review-line-plan (file)
  "The rows the diff shows for FILE, in order.
Each row is one of (context OLD NEW COMMENTABLE), (del OLD TEXT),
\(add NEW TEXT), or (gap INDEX HIDDEN) for a run of HIDDEN unchanged
lines in region INDEX.  TEXT is the hunk's copy of the line, used
when the file contents are missing."
  (let ((regions (gh-review--regions file))
        (hunks (gh-review-file-hunks file))
        (gaps (gh-review-file-gaps file))
        (rows nil))
    (when hunks
      (dolist (region regions)
        (let* ((start (plist-get region :start))
               (end (plist-get region :end))
               (delta (plist-get region :delta))
               (shown (gh-review--region-shown region gaps)))
          (cl-flet ((context (new)
                      (push (list 'context (+ new delta) new
                                  (or (and (not (plist-get region :first))
                                           (<= (- new start) 2))
                                      (and (not (plist-get region :last))
                                           (<= (- end new) 2))))
                            rows)))
            (when (<= start end)
              (if (eq shown 'all)
                  (cl-loop for new from start to end do (context new))
                (cl-loop for new from start below (+ start (car shown))
                         do (context new))
                (push (list 'gap (plist-get region :index)
                            (- (1+ (- end start)) (car shown) (cdr shown)))
                      rows)
                (cl-loop for new from (1+ (- end (cdr shown))) to end
                         do (context new)))))
          (when-let* ((hunk (nth (plist-get region :index) hunks)))
            (let ((old (gh-review-hunk-old-start hunk))
                  (new (gh-review-hunk-new-start hunk)))
              (when (zerop (gh-review-hunk-old-count hunk)) (cl-incf old))
              (when (zerop (gh-review-hunk-new-count hunk)) (cl-incf new))
              (dolist (line (gh-review-hunk-lines hunk))
                (if (eq (car line) 'del)
                    (progn (push (list 'del old (cdr line)) rows)
                           (cl-incf old))
                  (push (list 'add new (cdr line)) rows)
                  (cl-incf new))))))))
    (nreverse rows)))

(defun gh-review-map-line (file line side)
  "The line of FILE's other side matching LINE on SIDE.
SIDE is `before' or `after'.  A line inside a change maps to the
line where that change starts on the other side."
  (let ((delta 0))
    (catch 'found
      (dolist (hunk (gh-review-file-hunks file))
        (let* ((old-start (gh-review-hunk-old-start hunk))
               (old-count (gh-review-hunk-old-count hunk))
               (new-start (gh-review-hunk-new-start hunk))
               (new-count (gh-review-hunk-new-count hunk))
               (first (if (eq side 'after)
                          (if (zerop new-count) (1+ new-start) new-start)
                        (if (zerop old-count) (1+ old-start) old-start)))
               (count (if (eq side 'after) new-count old-count)))
          (cond
           ((< line first)
            (throw 'found (max 1 (if (eq side 'after)
                                     (+ line delta)
                                   (- line delta)))))
           ((< line (+ first count))
            (throw 'found (max 1 (if (eq side 'after) old-start new-start)))))
          (setq delta (+ delta (- old-count new-count)))))
      (max 1 (if (eq side 'after) (+ line delta) (- line delta))))))

;;; Syntax highlighting

(defvar gh-review--fontify-cache (make-hash-table :test #'equal)
  "Highlighted line vectors keyed by (PATH . BLOB).")

(defun gh-review--fontify-lines (path lines)
  "LINES of the file at PATH with the highlighting of PATH's mode.
LINES is a vector of strings; return a vector of the same length."
  (let ((size (seq-reduce (lambda (sum line) (+ sum (length line) 1)) lines 0)))
    (if (or (not gh-review-fontify) (> size gh-review-fontify-max-size)
            (zerop (length lines)))
        lines
      (with-temp-buffer
        (insert (mapconcat #'identity lines "\n"))
        (condition-case nil
            (progn
              ;; Mode hooks stay off: they start language servers and
              ;; other per-file machinery a scratch buffer has no use for.
              (let ((buffer-file-name path))
                (delay-mode-hooks (set-auto-mode t)))
              (font-lock-ensure)
              (let ((result (vconcat (split-string (buffer-string) "\n"))))
                (if (= (length result) (length lines)) result lines)))
          (error lines))))))

(defun gh-review--file-lines (file side)
  "The possibly highlighted lines of FILE's SIDE, `before' or `after'."
  (let ((lines (if (eq side 'before) (gh-review-file-old-lines file)
                 (gh-review-file-new-lines file)))
        (blob (if (eq side 'before) (gh-review-file-old-blob file)
                (gh-review-file-new-blob file)))
        (path (if (eq side 'before) (gh-review-file-old-path file)
                (gh-review-file-path file))))
    (if (or (null lines) (null blob))
        (or lines [])
      (let ((key (cons path blob)))
        (or (gethash key gh-review--fontify-cache)
            (puthash key (gh-review--fontify-lines path lines)
                     gh-review--fontify-cache))))))

;;; Buffer state

(defvar-local gh-review--only-paths nil
  "When non-nil, the paths this diff buffer is limited to.")

(defvar-local gh-review--expanded-threads nil
  "Ids of resolved threads shown in full.")

(defun gh-review--line-at (&optional position)
  "The line plist of the diff row at POSITION, or nil."
  (get-text-property (or position (point)) 'gh-review-line))

(defun gh-review-file-at-point ()
  "The `gh-review-file' of the card at point, or nil."
  (get-text-property (point) 'gh-review-file))

(defun gh-review-line-at-point ()
  "Location of the diff line at point as a plist, or nil.
The plist has :path, :side (\"LEFT\" or \"RIGHT\"), :line, :old and
:new line numbers, :kind (`context', `add' or `del'), :commentable,
and :text, the line's contents."
  (gh-review--line-at))

(defun gh-review-annotation-at-point ()
  "The annotation plist drawn at point, or nil."
  (get-text-property (point) 'gh-review-annotation))

;;; Rendering

(defun gh-review--status-marker (file)
  "The status letter of FILE with its face."
  (pcase (gh-review-file-status file)
    ('added (propertize "A" 'face 'gh-review-status-added))
    ('deleted (propertize "D" 'face 'gh-review-status-deleted))
    ('renamed (propertize "R" 'face 'gh-review-status-renamed))
    ('copied (propertize "C" 'face 'gh-review-status-renamed))
    (_ (propertize "M" 'face 'gh-review-status-modified))))

(defun gh-review--viewed-p (pr file)
  "Whether FILE of PR is marked as viewed on GitHub."
  (cdr (assoc (gh-review-file-path file) (gh-review-pr-viewed pr))))

(defun gh-review--initially-collapsed (pr file)
  "Whether FILE of PR starts folded."
  (or (gh-review--viewed-p pr file)
      (gh-review-file-binary file)
      (> (+ (gh-review-file-additions file) (gh-review-file-deletions file))
         gh-review-collapse-file-lines)
      (seq-some (lambda (regexp)
                  (string-match-p regexp (gh-review-file-path file)))
                gh-review-collapse-file-regexps)))

(defun gh-review--date (timestamp)
  "The date part of the ISO 8601 TIMESTAMP."
  (if (and timestamp (>= (length timestamp) 10))
      (substring timestamp 0 10)
    ""))

(defun gh-review--insert-block (indent face lines properties)
  "Insert LINES, each prefixed by INDENT, with FACE and PROPERTIES.
LINES are strings that may carry faces of their own."
  (dolist (line lines)
    (let ((start (point)))
      (insert (propertize indent 'gh-review-gutter t) line "\n")
      (add-face-text-property start (point) face t)
      (add-text-properties start (point) properties))))

(defun gh-review--body-lines (body)
  "BODY split into lines, with trailing blank lines dropped."
  (split-string (string-trim-right (or body "")) "\n"))

(defun gh-review--insert-thread (thread indent)
  "Insert review THREAD as a block indented by INDENT."
  (let* ((comments (gh-review--nodes thread 'comments))
         (resolved (alist-get 'isResolved thread))
         (expanded (or (not resolved)
                       (member (alist-get 'id thread)
                               gh-review--expanded-threads)))
         (properties (list 'gh-review-thread thread))
         (first t))
    (if (not expanded)
        (gh-review--insert-block
         indent 'gh-review-thread
         (list (propertize
                (format "✓ Resolved thread, %d comment%s by %s (RET to show)"
                        (length comments) (if (cdr comments) "s" "")
                        (string-join
                         (delete-dups
                          (mapcar (lambda (c) (gh-review--dig c 'author 'login))
                                  comments))
                         ", "))
                'face 'gh-review-resolved))
         properties)
      (dolist (comment comments)
        (gh-review--insert-block
         indent 'gh-review-thread
         (cons (concat (if first "┃ " "┃ ↳ ")
                       (propertize (or (gh-review--dig comment 'author 'login)
                                       "ghost")
                                   'face 'gh-review-thread-author)
                       (propertize (concat "  " (gh-review--date
                                                 (alist-get 'createdAt comment))
                                           (if (and first resolved)
                                               "  ✓ resolved" ""))
                                   'face 'gh-review-meta))
               (mapcar (lambda (line) (concat "┃   " line))
                       (gh-review--body-lines (alist-get 'body comment))))
         (append properties (list 'gh-review-comment comment)))
        (setq first nil)))))

(defun gh-review--insert-draft (draft indent)
  "Insert the pending comment DRAFT as a block indented by INDENT."
  (gh-review--insert-block
   indent 'gh-review-draft
   (cons (concat "✎ "
                 (propertize "Pending comment" 'face 'gh-review-thread-author)
                 (propertize
                  (concat (if (plist-get draft :start-line)
                              (format "  lines %d–%d" (plist-get draft :start-line)
                                      (plist-get draft :line))
                            "")
                          "  (sent with the review; RET edits, x deletes)")
                  'face 'gh-review-meta))
         (mapcar (lambda (line) (concat "  " line))
                 (gh-review--body-lines (plist-get draft :body))))
   (list 'gh-review-draft draft)))

(defun gh-review--insert-annotation (annotation indent)
  "Insert ANNOTATION as a block indented by INDENT."
  (gh-review--insert-block
   indent (or (plist-get annotation :face) 'gh-review-annotation)
   (cons (concat "◆ " (propertize (or (plist-get annotation :heading) "")
                                  'face 'gh-review-thread-author))
         (mapcar (lambda (line) (concat "  " line))
                 (gh-review--body-lines (plist-get annotation :body))))
   (list 'gh-review-annotation annotation)))

(defun gh-review--anchored (items path side line)
  "The ITEMS anchored at PATH, SIDE and LINE.
ITEMS are (KEY . ITEM) conses whose KEY is (PATH SIDE LINE)."
  (let ((key (list path side line)))
    (delq nil (mapcar (lambda (item) (and (equal (car item) key) (cdr item)))
                      items))))

(defun gh-review--annotations (pr)
  "Every annotation the hook functions contribute for PR."
  (mapcan (lambda (function) (copy-sequence (funcall function pr)))
          gh-review-annotation-functions))

(defun gh-review--attachments (pr path)
  "Threads, drafts and annotations of PR's file PATH.
Return a plist: :anchored is a list of (KEY KIND . ITEM) entries
keyed by (PATH SIDE LINE); :loose lists (KIND . ITEM) entries with
no current line."
  (let (anchored loose)
    (dolist (thread (gh-review-pr-threads pr))
      (when (equal (alist-get 'path thread) path)
        (if (and (alist-get 'line thread) (not (alist-get 'isOutdated thread)))
            (push (cons (list path (alist-get 'diffSide thread)
                              (alist-get 'line thread))
                        (cons 'thread thread))
                  anchored)
          (push (cons 'thread thread) loose))))
    (dolist (draft (gh-review-pr-drafts pr))
      (when (equal (plist-get draft :path) path)
        (push (cons (list path (plist-get draft :side) (plist-get draft :line))
                    (cons 'draft draft))
              anchored)))
    (dolist (annotation (gh-review--annotations pr))
      (when (equal (plist-get annotation :path) path)
        (if (plist-get annotation :line)
            (push (cons (list path (or (plist-get annotation :side) "RIGHT")
                              (plist-get annotation :line))
                        (cons 'annotation annotation))
                  anchored)
          (push (cons 'annotation annotation) loose))))
    (list :anchored (nreverse anchored) :loose (nreverse loose))))

(defun gh-review--insert-attachment (attachment indent)
  "Insert ATTACHMENT, a (KIND . ITEM) cons, indented by INDENT."
  (pcase (car attachment)
    ('thread (gh-review--insert-thread (cdr attachment) indent))
    ('draft (gh-review--insert-draft (cdr attachment) indent))
    ('annotation (gh-review--insert-annotation (cdr attachment) indent))))

(defun gh-review--gutter-width (file)
  "Digits the line numbers of FILE need."
  (max 3 (length (number-to-string
                  (max (length (gh-review-file-old-lines file))
                       (length (gh-review-file-new-lines file)))))))

(defun gh-review--insert-row (file row width old-lines new-lines)
  "Insert the diff ROW of FILE with line numbers WIDTH digits wide.
OLD-LINES and NEW-LINES are the sides' highlighted lines.  Return
the row's line plist, or nil for a hidden-lines row."
  (let* ((path (gh-review-file-path file))
         (blank (make-string width ?\s))
         (number (lambda (n) (format (format "%%%dd" width) n))))
    (pcase row
      (`(gap ,index ,hidden)
       (let ((start (point)))
         (insert (propertize (concat blank " " blank "  ⋯ ")
                             'gh-review-gutter t)
                 (format "%d hidden line%s  " hidden (if (= hidden 1) "" "s")))
         (insert-text-button "[↑ expand]" 'action
                             (lambda (_) (gh-review--expand-gap file index 'up))
                             'follow-link t 'help-echo "Show more lines above")
         (insert " ")
         (insert-text-button "[↓ expand]" 'action
                             (lambda (_) (gh-review--expand-gap file index 'down))
                             'follow-link t 'help-echo "Show more lines below")
         (insert " ")
         (insert-text-button "[all]" 'action
                             (lambda (_) (gh-review--expand-gap file index 'all))
                             'follow-link t 'help-echo "Show every hidden line")
         (insert "\n")
         (add-face-text-property start (point) 'gh-review-gap t)
         (put-text-property start (point) 'gh-review-gap (cons file index))
         nil))
      (`(context ,old ,new ,commentable)
       (let ((start (point))
             (text (if (<= new (length new-lines)) (aref new-lines (1- new)) "")))
         (insert (propertize (concat (funcall number old) " "
                                     (funcall number new) "   ")
                             'face 'gh-review-gutter 'gh-review-gutter t)
                 text "\n")
         (let ((line (list :path path :side "RIGHT" :line new :old old :new new
                           :kind 'context :commentable commentable
                           :text (substring-no-properties text))))
           (put-text-property start (point) 'gh-review-line line)
           line)))
      (`(,(and kind (or 'add 'del)) ,n ,fallback)
       (let* ((start (point))
              (lines (if (eq kind 'add) new-lines old-lines))
              (text (if (<= n (length lines)) (aref lines (1- n)) fallback)))
         (insert (propertize (concat (if (eq kind 'del) (funcall number n) blank)
                                     " "
                                     (if (eq kind 'add) (funcall number n) blank)
                                     (if (eq kind 'add) " + " " - "))
                             'face (if (eq kind 'add) 'gh-review-added-gutter
                                     'gh-review-removed-gutter)
                             'gh-review-gutter t)
                 text "\n")
         (add-face-text-property (+ start (* 2 width) 4) (point)
                                 (if (eq kind 'add) 'gh-review-added
                                   'gh-review-removed)
                                 t)
         (let ((line (list :path path
                           :side (if (eq kind 'add) "RIGHT" "LEFT")
                           :line n
                           :old (and (eq kind 'del) n)
                           :new (and (eq kind 'add) n)
                           :kind kind :commentable t
                           :text (substring-no-properties text))))
           (put-text-property start (point) 'gh-review-line line)
           line))))))

(defun gh-review--insert-file-header (pr file)
  "Insert the header band of PR's FILE."
  (let ((start (point))
        (viewed (gh-review--viewed-p pr file)))
    (insert (if (gh-review-file-collapsed file) "▸ " "▾ ")
            (gh-review--status-marker file) "  "
            (if (memq (gh-review-file-status file) '(renamed copied))
                (concat (propertize (gh-review-file-old-path file)
                                    'face 'gh-review-meta)
                        " → ")
              "")
            (propertize (gh-review-file-path file) 'face 'gh-review-file-path)
            "  "
            (propertize (format "+%d" (gh-review-file-additions file))
                        'face 'gh-review-status-added)
            " "
            (propertize (format "−%d" (gh-review-file-deletions file))
                        'face 'gh-review-status-deleted)
            (if viewed (propertize "   ✓ viewed" 'face 'gh-review-meta) "")
            (if (and (gh-review-file-new-mode file) (gh-review-file-old-mode file))
                (propertize (format "   mode %s → %s"
                                    (gh-review-file-old-mode file)
                                    (gh-review-file-new-mode file))
                            'face 'gh-review-meta)
              "")
            "\n")
    (add-face-text-property start (point) 'gh-review-file-header t)
    (put-text-property start (point) 'gh-review-file-header t)))

(defun gh-review--insert-file (pr file)
  "Insert the card of PR's FILE at point."
  (let ((start (point))
        (attachments (gh-review--attachments pr (gh-review-file-path file)))
        body)
    (insert (propertize "\n" 'face '(:height 0.5)))
    (gh-review--insert-file-header pr file)
    (setq body (point))
    (let ((width (gh-review--gutter-width file))
          (anchored (plist-get attachments :anchored))
          (indent (make-string (+ (* 2 (gh-review--gutter-width file)) 4) ?\s))
          (old-lines (gh-review--file-lines file 'before))
          (new-lines (gh-review--file-lines file 'after))
          (shown nil))
      (dolist (attachment (plist-get attachments :loose))
        (gh-review--insert-attachment attachment "  "))
      (cond
       ((gh-review-file-binary file)
        (insert (propertize "  Binary file\n" 'face 'gh-review-meta)))
       ((null (gh-review-file-hunks file))
        (insert (propertize (if (eq (gh-review-file-status file) 'renamed)
                                "  Renamed without changes\n"
                              "  No content changes\n")
                            'face 'gh-review-meta)))
       (t
        (dolist (row (gh-review-line-plan file))
          (when-let* ((line (gh-review--insert-row file row width
                                                   old-lines new-lines)))
            (let ((keys (if (eq (plist-get line :kind) 'context)
                            (list (list (plist-get line :path) "RIGHT"
                                        (plist-get line :new))
                                  (list (plist-get line :path) "LEFT"
                                        (plist-get line :old)))
                          (list (list (plist-get line :path)
                                      (plist-get line :side)
                                      (plist-get line :line))))))
              (dolist (key keys)
                (push key shown)
                (dolist (attachment (gh-review--anchored anchored
                                                         (nth 0 key)
                                                         (nth 1 key)
                                                         (nth 2 key)))
                  (gh-review--insert-attachment attachment indent))))))))
      ;; Comments on lines the diff currently hides go to the end of
      ;; the card, with their line, so expanding is the way to their
      ;; context.
      (let ((hidden (seq-remove (lambda (entry) (member (car entry) shown))
                                anchored)))
        (dolist (entry hidden)
          (insert (propertize (format "  On %s line %d:\n"
                                      (if (equal (nth 1 (car entry)) "LEFT")
                                          "old" "new")
                                      (nth 2 (car entry)))
                              'face 'gh-review-meta))
          (gh-review--insert-attachment (cdr entry) "  ")))
      (put-text-property start (point) 'gh-review-file file)
      (let ((overlay (make-overlay body (point) nil t nil)))
        (overlay-put overlay 'gh-review-fold t)
        (overlay-put overlay 'evaporate t)
        (overlay-put overlay 'invisible
                     (and (gh-review-file-collapsed file) 'gh-review-fold))))))

(defun gh-review--file-bounds (file)
  "Start and end of FILE's card in the current buffer, or nil."
  (when-let* ((start (text-property-any (point-min) (point-max)
                                        'gh-review-file file)))
    (cons start (or (next-single-property-change start 'gh-review-file)
                    (point-max)))))

(defun gh-review--position-key ()
  "A description of point that survives re-rendering."
  (let ((line (gh-review--line-at))
        (file (gh-review-file-at-point)))
    (cond (line (list 'line (plist-get line :path) (plist-get line :side)
                      (plist-get line :line)))
          (file (list 'file (gh-review-file-path file)
                      (- (point) (car (gh-review--file-bounds file)))))
          (t (list 'point (point))))))

(defun gh-review--line-matches-p (target value)
  "Whether the line plist VALUE is at TARGET, a (PATH SIDE LINE) list."
  (and value
       (equal (plist-get value :path) (nth 0 target))
       (or (and (equal (plist-get value :side) (nth 1 target))
                (eql (plist-get value :line) (nth 2 target)))
           (and (eq (plist-get value :kind) 'context)
                (equal (nth 1 target) "LEFT")
                (eql (plist-get value :old) (nth 2 target))))))

(defun gh-review--restore-position (key)
  "Move point to the place KEY describes."
  (pcase key
    (`(line ,path ,side ,line)
     (goto-char (point-min))
     (let ((match (text-property-search-forward
                   'gh-review-line (list path side line)
                   #'gh-review--line-matches-p)))
       (if match
           (goto-char (prop-match-beginning match))
         (gh-review--restore-position (list 'file path 0)))))
    (`(file ,path ,offset)
     (if-let* ((file (seq-find (lambda (f) (equal (gh-review-file-path f) path))
                               (gh-review-pr-files gh-review-buffer-pr)))
               (bounds (gh-review--file-bounds file)))
         (goto-char (min (+ (car bounds) offset) (1- (cdr bounds))))
       (goto-char (point-min))))
    (`(point ,position) (goto-char (min position (point-max))))))

(defun gh-review--rerender-file (file)
  "Redraw FILE's card in place, keeping point where it was."
  (when-let* ((bounds (gh-review--file-bounds file)))
    (let ((inhibit-read-only t)
          (key (gh-review--position-key))
          (start (window-start)))
      (save-excursion
        (delete-region (car bounds) (cdr bounds))
        (goto-char (car bounds))
        (gh-review--insert-file gh-review-buffer-pr file))
      (gh-review--restore-position key)
      (when (get-buffer-window)
        (set-window-start (get-buffer-window) start t)))))

(defun gh-review--checks-summary (pr)
  "A short string describing PR's status checks."
  (let* ((checks (gh-review-pr-checks pr))
         (state (plist-get checks :state))
         (contexts (plist-get checks :contexts)))
    (if (null state)
        "no checks"
      (format "checks %s (%d)"
              (propertize (downcase state)
                          'face (pcase state
                                  ("SUCCESS" 'success)
                                  ((or "FAILURE" "ERROR") 'error)
                                  (_ 'warning)))
              (length contexts)))))

(defun gh-review--insert-header (pr)
  "Insert the summary at the top of PR's diff buffer."
  (insert (propertize (or (gh-review-pr-title pr) (gh-review-pr-key pr))
                      'face 'gh-review-title)
          "\n")
  (insert (propertize
           (format "%s · %s wants to merge %s into %s · %s%s · %s%s\n"
                   (gh-review-pr-key pr)
                   (or (gh-review-pr-author pr) "?")
                   (or (gh-review-pr-head-ref pr) "?")
                   (or (gh-review-pr-base-ref pr) "?")
                   (downcase (or (gh-review-pr-state pr) "?"))
                   (if (gh-review-pr-draft pr) " (draft)" "")
                   (gh-review--checks-summary pr)
                   (if (gh-review-pr-review-decision pr)
                       (format " · %s" (downcase (replace-regexp-in-string
                                                   "_" " "
                                                   (gh-review-pr-review-decision pr))))
                     ""))
           'face 'gh-review-meta))
  (let ((files (gh-review-pr-files pr)))
    (insert (propertize
             (format "%s %s in %d file%s · %d viewed%s\n"
                     (propertize (format "+%d" (or (gh-review-pr-additions pr) 0))
                                 'face 'gh-review-status-added)
                     (propertize (format "−%d" (or (gh-review-pr-deletions pr) 0))
                                 'face 'gh-review-status-deleted)
                     (length files) (if (= (length files) 1) "" "s")
                     (seq-count (lambda (file) (gh-review--viewed-p pr file)) files)
                     (if (gh-review-pr-drafts pr)
                         (format " · %d pending comment%s"
                                 (length (gh-review-pr-drafts pr))
                                 (if (cdr (gh-review-pr-drafts pr)) "s" ""))
                       ""))
             'face 'gh-review-meta)))
  (dolist (annotation (gh-review--annotations pr))
    (unless (plist-get annotation :path)
      (gh-review--insert-annotation annotation ""))))

(defun gh-review-render ()
  "Redraw the whole diff buffer from its pull request."
  (let* ((pr gh-review-buffer-pr)
         (inhibit-read-only t)
         (key (gh-review--position-key)))
    (erase-buffer)
    (remove-overlays)
    (pcase (gh-review-pr-status pr)
      ((or 'new 'loading)
       (insert (propertize (format "Loading %s…\n" (gh-review-pr-key pr))
                           'face 'gh-review-meta)))
      ('error
       (insert (propertize (format "Could not load %s\n\n" (gh-review-pr-key pr))
                           'face 'error)
               (or (gh-review-pr-error pr) "") "\n"))
      (_
       (gh-review--insert-header pr)
       (dolist (file (gh-review-pr-files pr))
         (when (or (null gh-review--only-paths)
                   (member (gh-review-file-path file) gh-review--only-paths))
           (gh-review--insert-file pr file)))))
    (gh-review--restore-position key)))

;;; The mode

(defvar-keymap gh-review-diff-mode-map
  :doc "Keymap of `gh-review-diff-mode'."
  :parent special-mode-map
  "RET" #'gh-review-visit
  "TAB" #'gh-review-toggle
  "<backtab>" #'gh-review-toggle-all
  "n" #'gh-review-next-file
  "p" #'gh-review-previous-file
  "N" #'gh-review-next-change
  "P" #'gh-review-previous-change
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
  "g" #'gh-review-refresh)

(defun gh-review--header-line ()
  "The header line: the pull request and the file at the window's top."
  (let* ((pr gh-review-buffer-pr)
         (file (and (window-start)
                    (get-text-property (window-start) 'gh-review-file))))
    (concat " " (propertize (gh-review-pr-key pr) 'face 'bold)
            (if file
                (concat "  " (gh-review--status-marker file) " "
                        (gh-review-file-path file))
              ""))))

(defun gh-review--filter-buffer-substring (beg end &optional delete)
  "The plain text between BEG and END without the line-number gutter.
DELETE is passed on to `buffer-substring--filter'."
  (let ((text (buffer-substring--filter beg end delete))
        (position 0) (pieces nil))
    (while (< position (length text))
      (let ((next (or (next-single-property-change position 'gh-review-gutter text)
                      (length text))))
        (unless (get-text-property position 'gh-review-gutter text)
          (push (substring-no-properties text position next) pieces))
        (setq position next)))
    (apply #'concat (nreverse pieces))))

(define-derived-mode gh-review-diff-mode special-mode "PR Diff"
  "Major mode of a pull request's diff.

\\{gh-review-diff-mode-map}"
  :interactive nil
  (setq truncate-lines t
        buffer-read-only t)
  (add-to-invisibility-spec '(gh-review-fold . t))
  (setq-local filter-buffer-substring-function #'gh-review--filter-buffer-substring)
  (setq-local revert-buffer-function (lambda (&rest _) (gh-review-refresh)))
  (setq header-line-format '(:eval (gh-review--header-line))))

(defun gh-review-diff-buffer (pr &optional paths)
  "The diff buffer of PR, created when missing.
With PATHS, a buffer limited to those files."
  (let ((name (if paths
                  (format "*%s %s (diff)*" (gh-review-pr-key pr)
                          (string-join paths ", "))
                (format "*%s*" (gh-review-pr-key pr)))))
    (or (get-buffer name)
        (with-current-buffer (get-buffer-create name)
          (gh-review-diff-mode)
          (setq gh-review-buffer-pr pr
                gh-review--only-paths paths)
          (current-buffer)))))

(defun gh-review-redisplay (pr)
  "Redraw every buffer showing PR."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (eq gh-review-buffer-pr pr)
        (cond ((derived-mode-p 'gh-review-diff-mode) (gh-review-render))
              ((and (derived-mode-p 'gh-review-conversation-mode)
                    (fboundp 'gh-review-conversation-render))
               (funcall 'gh-review-conversation-render)))))))

(defvar gh-review-refresh-hook nil
  "Hook run with the pull request after a refresh redrew its buffers.")

(defun gh-review-load (pr &optional callback)
  "Fetch PR, prepare its files' display state, and redraw its buffers.
CALLBACK, when given, is called with PR afterwards."
  (gh-review-load-drafts pr)
  (gh-review-fetch
   pr
   (lambda (pr)
     (when (eq (gh-review-pr-status pr) 'ready)
       (dolist (file (gh-review-pr-files pr))
         (unless (gh-review-file-gaps file)
           (setf (gh-review-file-collapsed file)
                 (gh-review--initially-collapsed pr file)))))
     (gh-review-redisplay pr)
     (run-hook-with-args 'gh-review-refresh-hook pr)
     (when callback (funcall callback pr))))
  (gh-review-redisplay pr))

(defun gh-review-refresh ()
  "Fetch the current pull request again and redraw it."
  (interactive)
  (gh-review-load (gh-review-current-pr))
  (message "Refreshing %s…" (gh-review-pr-key (gh-review-current-pr))))

;;; Folding and expansion

(defun gh-review--require-file ()
  "The file card at point, or a user error."
  (or (gh-review-file-at-point) (user-error "Not on a file")))

(defun gh-review-toggle ()
  "Fold or unfold what point is on: a resolved thread or a file card."
  (interactive)
  (if-let* ((thread (get-text-property (point) 'gh-review-thread))
            ((alist-get 'isResolved thread)))
      (let ((id (alist-get 'id thread)))
        (setq gh-review--expanded-threads
              (if (member id gh-review--expanded-threads)
                  (delete id gh-review--expanded-threads)
                (cons id gh-review--expanded-threads)))
        (gh-review--rerender-file (gh-review--require-file)))
    (let ((file (gh-review--require-file)))
      (setf (gh-review-file-collapsed file) (not (gh-review-file-collapsed file)))
      (gh-review--rerender-file file)
      (goto-char (car (gh-review--file-bounds file)))
      (forward-line 1))))

(defun gh-review-toggle-all ()
  "Fold every file card, or unfold them all when all are folded."
  (interactive)
  (let* ((pr (gh-review-current-pr))
         (fold (seq-some (lambda (file) (not (gh-review-file-collapsed file)))
                         (gh-review-pr-files pr))))
    (dolist (file (gh-review-pr-files pr))
      (setf (gh-review-file-collapsed file) fold))
    (gh-review-render)))

(defun gh-review--expand-gap (file index direction)
  "Reveal lines of FILE's unchanged region INDEX.
DIRECTION is `up' to extend the context above the next change,
`down' to extend the context below the previous change, `both', or
`all'."
  (let* ((region (nth index (gh-review--regions file)))
         (shown (gh-review--region-shown region (gh-review-file-gaps file))))
    (unless (eq shown 'all)
      (setf (alist-get index (gh-review-file-gaps file))
            (pcase direction
              ('all 'all)
              ('up (cons (car shown) (+ (cdr shown) gh-review-expand-step)))
              ('down (cons (+ (car shown) gh-review-expand-step) (cdr shown)))
              (_ (cons (+ (car shown) gh-review-expand-step)
                       (+ (cdr shown) gh-review-expand-step))))))
    (gh-review--rerender-file file)))

(defun gh-review-expand-more (&optional all)
  "Reveal more unchanged lines at the hidden-lines row at point.
With a prefix argument ALL, reveal every line of the row.  On a
line next to a row rather than on one, the nearest row below
expands."
  (interactive "P")
  (let ((gap (or (get-text-property (point) 'gh-review-gap)
                 (save-excursion
                   (when-let* ((match (text-property-search-forward
                                       'gh-review-gap nil
                                       (lambda (_ value) value))))
                     (prop-match-value match))))))
    (unless gap (user-error "No hidden lines below point"))
    (gh-review--expand-gap (car gap) (cdr gap) (if all 'all 'both))))

(defun gh-review-expand-less ()
  "Hide the context of the current file again."
  (interactive)
  (let ((file (gh-review--require-file)))
    (setf (gh-review-file-gaps file) nil)
    (gh-review--rerender-file file)))

(defun gh-review-expand-file ()
  "Show every line of the current file inside its diff."
  (interactive)
  (let ((file (gh-review--require-file)))
    (setf (gh-review-file-gaps file)
          (mapcar (lambda (region) (cons (plist-get region :index) 'all))
                  (gh-review--regions file))
          (gh-review-file-collapsed file) nil)
    (gh-review--rerender-file file)))

;;; Navigation

(defun gh-review--move-to-property (property forward)
  "Move to the next start of a run of PROPERTY, or the previous unless FORWARD."
  (let ((match (if forward
                   (progn
                     (when (get-text-property (point) property)
                       (goto-char (or (next-single-property-change (point) property)
                                      (point-max))))
                     (text-property-search-forward property t t))
                 (when (get-text-property (point) property)
                   (goto-char (or (previous-single-property-change (point) property)
                                  (point-min))))
                 (text-property-search-backward property t t))))
    (when match (goto-char (prop-match-beginning match)))
    match))

(defun gh-review-next-file ()
  "Move to the next file header."
  (interactive)
  (unless (gh-review--move-to-property 'gh-review-file-header t)
    (user-error "No next file"))
  (gh-review--follow))

(defun gh-review-previous-file ()
  "Move to the previous file header."
  (interactive)
  (unless (gh-review--move-to-property 'gh-review-file-header nil)
    (user-error "No previous file"))
  (gh-review--follow))

(defun gh-review--change-start-p (position)
  "Whether POSITION starts a run of added or removed lines."
  (let ((line (gh-review--line-at position))
        (previous (and (> position (point-min))
                       (save-excursion
                         (goto-char position)
                         (forward-line -1)
                         (gh-review--line-at)))))
    (and line (memq (plist-get line :kind) '(add del))
         (not (and previous (memq (plist-get previous :kind) '(add del)))))))

(defun gh-review-next-change ()
  "Move to the start of the next run of changed lines."
  (interactive)
  (let ((start (point)) found)
    (forward-line 1)
    (while (and (not (eobp)) (not (setq found (gh-review--change-start-p (point)))))
      (forward-line 1))
    (unless found
      (goto-char start)
      (user-error "No next change"))
    (gh-review--follow)))

(defun gh-review-previous-change ()
  "Move to the start of the previous run of changed lines."
  (interactive)
  (let ((start (point)) found)
    (forward-line -1)
    (while (and (not (bobp)) (not (setq found (gh-review--change-start-p (point)))))
      (forward-line -1))
    (unless (or found (gh-review--change-start-p (point)))
      (goto-char start)
      (user-error "No previous change"))
    (gh-review--follow)))

(defun gh-review--follow ()
  "Let the file tree follow the file at point."
  (when-let* ((file (gh-review-file-at-point))
              ((fboundp 'gh-review-tree-follow)))
    (gh-review-tree-follow (gh-review-file-path file))))

(defun gh-review-goto-file (path)
  "Move point to the header of PATH's card, unfolding it."
  (let* ((pr (gh-review-current-pr))
         (file (or (gh-review-pr-file pr path)
                   (user-error "%s is not changed in %s" path (gh-review-pr-key pr)))))
    (when (gh-review-file-collapsed file)
      (setf (gh-review-file-collapsed file) nil)
      (gh-review--rerender-file file))
    (if-let* ((bounds (gh-review--file-bounds file)))
        (progn (goto-char (car bounds))
               (forward-line 1)
               (when-let* ((window (get-buffer-window)))
                 (set-window-start window (car bounds))))
      (user-error "%s is not shown in this buffer" path))))

;;; Before and after views

(defvar-local gh-review--blob-file nil
  "The `gh-review-file' a blob buffer shows, or nil for an unchanged file.")

(defvar-local gh-review--blob-side nil
  "The side a blob buffer shows: `before' or `after'.")

(defvar-local gh-review--blob-path nil
  "The path a blob buffer shows.")

(defvar-keymap gh-review-blob-mode-map
  :doc "Keymap of `gh-review-blob-mode'."
  "C-c C-n" #'gh-review-blob-next-change
  "C-c C-p" #'gh-review-blob-previous-change
  "C-c C-o" #'gh-review-blob-other-side
  "C-c C-d" #'gh-review-blob-diff)

(define-minor-mode gh-review-blob-mode
  "Minor mode of a buffer showing one side of a pull request's file.

\\{gh-review-blob-mode-map}"
  :lighter " PR-file"
  :keymap gh-review-blob-mode-map)

(defun gh-review--blob-buffer (pr path side)
  "A read-only buffer of PATH in PR on SIDE, `before' or `after'."
  (let* ((file (or (gh-review-pr-file pr path)
                   (seq-find (lambda (f) (equal (gh-review-file-old-path f) path))
                             (gh-review-pr-files pr))))
         (name (format "%s %s@%s" (gh-review-pr-key pr) path
                       (if (eq side 'before) "base" "head")))
         (buffer (get-buffer name)))
    (when (and file (eq side 'before) (eq (gh-review-file-status file) 'added))
      (user-error "%s is new in this pull request" path))
    (when (and file (eq side 'after) (eq (gh-review-file-status file) 'deleted))
      (user-error "%s is deleted by this pull request" path))
    (unless buffer
      (setq buffer (get-buffer-create name))
      (with-current-buffer buffer
        (let ((inhibit-read-only t)
              (side-path (if (and file (eq side 'before))
                             (gh-review-file-old-path file)
                           path)))
          (insert (if file
                      (mapconcat #'identity
                                 (if (eq side 'before)
                                     (gh-review-file-old-lines file)
                                   (gh-review-file-new-lines file))
                                 "\n")
                    (gh-review-file-contents pr side-path side)))
          (let ((buffer-file-name side-path))
            (delay-mode-hooks (set-auto-mode t)))
          (setq buffer-read-only t
                gh-review-buffer-pr pr
                gh-review--blob-file file
                gh-review--blob-side side
                gh-review--blob-path path)
          (setq-local default-directory
                      (file-name-as-directory gh-review-cache-directory))
          (gh-review-blob-mode 1)
          (when file (gh-review--highlight-blob file side))
          (goto-char (point-min)))))
    buffer))

(defun gh-review--highlight-blob (file side)
  "Highlight the lines FILE's pull request changes on SIDE."
  (save-excursion
    (dolist (hunk (gh-review-file-hunks file))
      (let ((start (if (eq side 'before) (gh-review-hunk-old-start hunk)
                     (gh-review-hunk-new-start hunk)))
            (count (if (eq side 'before) (gh-review-hunk-old-count hunk)
                     (gh-review-hunk-new-count hunk))))
        (when (> count 0)
          (goto-char (point-min))
          (forward-line (1- start))
          (let ((overlay (make-overlay (point)
                                       (progn (forward-line count) (point)))))
            (overlay-put overlay 'face (if (eq side 'before) 'gh-review-removed
                                         'gh-review-added))
            (overlay-put overlay 'gh-review-change t)))))))

(defun gh-review--target (side)
  "The path and line to open for SIDE from point in a diff buffer.
Return (PATH . LINE); LINE is nil off a code line."
  (let ((line (gh-review--line-at))
        (file (gh-review-file-at-point)))
    (cond
     (line
      (let ((number (if (eq side 'before)
                        (or (plist-get line :old)
                            (and file (gh-review-map-line
                                       file (plist-get line :new) 'after)))
                      (or (plist-get line :new)
                          (and file (gh-review-map-line
                                     file (plist-get line :old) 'before))))))
        (cons (plist-get line :path) number)))
     (file (cons (gh-review-file-path file) nil))
     (t (cons (completing-read "File: " (gh-review-all-paths (gh-review-current-pr))
                               nil t)
              nil)))))

(defun gh-review-show-side (pr path side &optional line)
  "Show PATH of PR on SIDE, `before' or `after', at LINE."
  (let ((buffer (gh-review--blob-buffer pr path side)))
    (pop-to-buffer buffer '((display-buffer-reuse-window
                             display-buffer-use-some-window)
                            (inhibit-same-window . t)))
    (when line
      (goto-char (point-min))
      (forward-line (1- line)))))

(defun gh-review-show-before ()
  "Show the file at point as it was at the merge base."
  (interactive)
  (let ((target (gh-review--target 'before)))
    (gh-review-show-side (gh-review-current-pr) (car target) 'before (cdr target))))

(defun gh-review-show-after ()
  "Show the file at point as it is at the pull request's head."
  (interactive)
  (let ((target (gh-review--target 'after)))
    (gh-review-show-side (gh-review-current-pr) (car target) 'after (cdr target))))

(defun gh-review-visit ()
  "Act on what point is on.
On a hidden-lines row, expand it; on a file header, fold or unfold
the card; on a resolved thread, show it; on a pending comment, edit
it; on a code line, show the file there, as it was for a removed
line and as it is otherwise."
  (interactive)
  (cond
   ((get-text-property (point) 'gh-review-gap) (gh-review-expand-more))
   ((get-text-property (point) 'gh-review-file-header) (gh-review-toggle))
   ((get-text-property (point) 'gh-review-draft) (gh-review-edit-draft))
   ((let ((thread (get-text-property (point) 'gh-review-thread)))
      (and thread (alist-get 'isResolved thread)))
    (gh-review-toggle))
   ((gh-review--line-at)
    (if (eq (plist-get (gh-review--line-at) :kind) 'del)
        (gh-review-show-before)
      (gh-review-show-after)))))

(defun gh-review-ediff ()
  "Compare the before and after of the file at point with ediff."
  (interactive)
  (let* ((pr (gh-review-current-pr))
         (path (car (gh-review--target 'after)))
         (file (gh-review-pr-file pr path)))
    (unless file (user-error "%s is not changed" path))
    (when (memq (gh-review-file-status file) '(added deleted))
      (user-error "%s exists on one side only" path))
    (ediff-buffers (gh-review--blob-buffer pr (gh-review-file-old-path file) 'before)
                   (gh-review--blob-buffer pr path 'after))))

(defun gh-review-file-diff (&optional path)
  "Show the diff of PATH, by default the file at point, with all context."
  (interactive)
  (let* ((pr (gh-review-current-pr))
         (path (or path (car (gh-review--target 'after))))
         (file (or (gh-review-pr-file pr path)
                   (user-error "%s is not changed" path)))
         (line (gh-review--line-at))
         (buffer (gh-review-diff-buffer pr (list path))))
    (setf (gh-review-file-gaps file)
          (mapcar (lambda (region) (cons (plist-get region :index) 'all))
                  (gh-review--regions file))
          (gh-review-file-collapsed file) nil)
    (with-current-buffer buffer (gh-review-render))
    (with-current-buffer (gh-review-diff-buffer pr)
      (gh-review--rerender-file file))
    (pop-to-buffer buffer '((display-buffer-reuse-window
                             display-buffer-same-window)))
    (when line
      (gh-review--restore-position
       (list 'line (plist-get line :path) (plist-get line :side)
             (plist-get line :line))))))

(defun gh-review--change-overlays (descending)
  "This buffer's change overlays sorted by start, last first if DESCENDING."
  (sort (seq-filter (lambda (o) (overlay-get o 'gh-review-change))
                    (overlays-in (point-min) (point-max)))
        (lambda (a b) (if descending
                          (> (overlay-start a) (overlay-start b))
                        (< (overlay-start a) (overlay-start b))))))

(defun gh-review-blob-next-change ()
  "Move to the next changed region of this file view."
  (interactive)
  (if-let* ((next (seq-find (lambda (o) (> (overlay-start o) (point)))
                            (gh-review--change-overlays nil))))
      (goto-char (overlay-start next))
    (user-error "No next change")))

(defun gh-review-blob-previous-change ()
  "Move to the previous changed region of this file view."
  (interactive)
  (if-let* ((previous (seq-find (lambda (o) (< (overlay-start o) (line-beginning-position)))
                                (gh-review--change-overlays t))))
      (goto-char (overlay-start previous))
    (user-error "No previous change")))

(defun gh-review-blob-other-side ()
  "Show the other side of this file at the matching line."
  (interactive)
  (let* ((line (line-number-at-pos))
         (other (if (eq gh-review--blob-side 'before) 'after 'before))
         (file gh-review--blob-file))
    (unless file (user-error "This file is unchanged"))
    (gh-review-show-side gh-review-buffer-pr
                         (if (eq other 'before) (gh-review-file-old-path file)
                           (gh-review-file-path file))
                         other (gh-review-map-line file line gh-review--blob-side))))

(defun gh-review-blob-diff ()
  "Show this file's diff at the line of point."
  (interactive)
  (let ((file gh-review--blob-file)
        (side gh-review--blob-side)
        (line (line-number-at-pos)))
    (unless file (user-error "This file is unchanged"))
    (gh-review-file-diff (gh-review-file-path file))
    (gh-review--restore-position
     (list 'line (gh-review-file-path file)
           (if (eq side 'before) "LEFT" "RIGHT") line))))

;;; Writing text

(defvar-local gh-review--editor-callback nil
  "Function the text of an editor buffer is passed to when finished.")

(defvar-keymap gh-review-editor-mode-map
  :doc "Keymap of `gh-review-editor-mode'."
  "C-c C-c" #'gh-review-editor-finish
  "C-c C-k" #'gh-review-editor-cancel)

(define-minor-mode gh-review-editor-mode
  "Minor mode of a buffer where a comment or review body is written.

\\{gh-review-editor-mode-map}"
  :lighter " PR-edit"
  :keymap gh-review-editor-mode-map)

(defun gh-review-edit-text (title initial callback &optional pr)
  "Open a buffer to write text under TITLE, starting from INITIAL.
CALLBACK receives the text when the user finishes; cancelling calls
nothing.  PR is the pull request the text belongs to."
  (let ((buffer (generate-new-buffer (format "*gh-review: %s*" title))))
    (with-current-buffer buffer
      (funcall gh-review-draft-major-mode)
      (gh-review-editor-mode 1)
      (setq gh-review-buffer-pr pr
            gh-review--editor-callback callback)
      (setq header-line-format
            (substitute-command-keys
             (format " %s   \\[gh-review-editor-finish] finish   \\[gh-review-editor-cancel] cancel"
                     title)))
      (insert (or initial ""))
      (goto-char (point-min)))
    (pop-to-buffer buffer '((display-buffer-below-selected)
                            (window-height . 0.3)))
    buffer))

(defun gh-review-editor-finish ()
  "Pass this buffer's text on and close it."
  (interactive)
  (let ((text (string-trim (buffer-string)))
        (callback gh-review--editor-callback))
    (quit-window t)
    (funcall callback text)))

(defun gh-review-editor-cancel ()
  "Close this buffer without using its text."
  (interactive)
  (quit-window t))

;;; Pending comments

(defun gh-review--draft-at-point ()
  "The pending comment at point, or a user error."
  (or (get-text-property (point) 'gh-review-draft)
      (user-error "No pending comment at point")))

(defun gh-review-add-draft (pr draft)
  "Add the pending comment DRAFT to PR, save, and redraw.
DRAFT is a plist with :path, :side, :line and :body, and optionally
:start-line and :start-side."
  (setf (gh-review-pr-drafts pr)
        (append (gh-review-pr-drafts pr)
                (list (plist-put (copy-sequence draft) :id
                                 (format "%x" (random most-positive-fixnum))))))
  (gh-review-save-drafts pr)
  (gh-review-redisplay pr))

(defun gh-review-comment (beg end)
  "Write a pending review comment on the line at point.
With an active region from BEG to END, the comment covers its lines,
which must be on one side of the diff."
  (interactive (if (use-region-p) (list (region-beginning) (region-end))
                 (list (point) (point))))
  (let* ((pr (gh-review-current-pr))
         (last (or (gh-review--line-at (save-excursion (goto-char end)
                                                       (when (and (> end beg) (bolp))
                                                         (forward-line -1))
                                                       (point)))
                   (user-error "Not on a line of the diff")))
         (first (or (gh-review--line-at beg) last)))
    (unless (and (plist-get first :commentable) (plist-get last :commentable))
      (user-error "GitHub accepts comments only within 3 lines of a change"))
    (unless (equal (plist-get first :side) (plist-get last :side))
      (user-error "A comment's lines must all be on one side"))
    (deactivate-mark)
    (gh-review-edit-text
     (format "comment on %s:%d" (plist-get last :path) (plist-get last :line))
     nil
     (lambda (body)
       (unless (string-empty-p body)
         (gh-review-add-draft
          pr (append (list :path (plist-get last :path)
                           :side (plist-get last :side)
                           :line (plist-get last :line)
                           :body body)
                     (unless (eq first last)
                       (list :start-line (plist-get first :line)
                             :start-side (plist-get first :side)))))))
     pr)))

(defun gh-review-edit-draft ()
  "Edit the pending comment at point."
  (interactive)
  (let ((pr (gh-review-current-pr))
        (draft (gh-review--draft-at-point)))
    (gh-review-edit-text
     (format "comment on %s:%d" (plist-get draft :path) (plist-get draft :line))
     (plist-get draft :body)
     (lambda (body)
       (setf (gh-review-pr-drafts pr)
             (if (string-empty-p body)
                 (remove draft (gh-review-pr-drafts pr))
               (mapcar (lambda (d) (if (eq d draft) (plist-put d :body body) d))
                       (gh-review-pr-drafts pr))))
       (gh-review-save-drafts pr)
       (gh-review-redisplay pr))
     pr)))

(defun gh-review-delete-draft ()
  "Delete the pending comment at point."
  (interactive)
  (let ((pr (gh-review-current-pr))
        (draft (gh-review--draft-at-point)))
    (when (y-or-n-p "Delete this pending comment? ")
      (setf (gh-review-pr-drafts pr) (remove draft (gh-review-pr-drafts pr)))
      (gh-review-save-drafts pr)
      (gh-review-redisplay pr))))

;;; Threads

(defun gh-review--thread-at-point ()
  "The review thread at point, or a user error."
  (or (get-text-property (point) 'gh-review-thread)
      (user-error "No review thread at point")))

(defun gh-review-reply ()
  "Reply to the review thread at point; the reply is posted at once."
  (interactive)
  (let* ((pr (gh-review-current-pr))
         (thread (gh-review--thread-at-point))
         (first (car (gh-review--nodes thread 'comments))))
    (gh-review-edit-text
     (format "reply on %s" (alist-get 'path thread))
     nil
     (lambda (body)
       (unless (string-empty-p body)
         (gh-review-reply-to-thread
          pr (alist-get 'databaseId first) body
          (lambda (_) (message "Reply posted") (gh-review-load pr)))))
     pr)))

(defun gh-review-toggle-resolved ()
  "Resolve the review thread at point, or unresolve a resolved one."
  (interactive)
  (let ((pr (gh-review-current-pr))
        (thread (gh-review--thread-at-point)))
    (gh-review-set-thread-resolved
     (alist-get 'id thread) (not (alist-get 'isResolved thread))
     (lambda () (gh-review-load pr)))))

;;; Viewed state

(defun gh-review-toggle-viewed ()
  "Mark the file at point as viewed on GitHub, or as not viewed.
A file marked viewed folds, and point moves to the next file."
  (interactive)
  (let* ((pr (gh-review-current-pr))
         (file (gh-review--require-file))
         (viewed (not (gh-review--viewed-p pr file)))
         (buffer (current-buffer)))
    (gh-review-set-file-viewed
     pr (gh-review-file-path file) viewed
     (lambda ()
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (setf (gh-review-file-collapsed file) viewed)
           (gh-review--rerender-file file)
           (when viewed
             (goto-char (car (gh-review--file-bounds file)))
             (ignore-errors (gh-review-next-file)))))))))

(provide 'gh-review-diff)
;;; gh-review-diff.el ends here
