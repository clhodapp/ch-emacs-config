;;; gh-review-ert.el --- Tests of gh-review -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; The parts of gh-review that do not need GitHub: reference parsing,
;; the diff parser, the line plan behind context expansion, line
;; mapping between the sides, the tree's grouping, rendering a pull
;; request record into a diff buffer, and the git round trip against
;; a local repository standing in for GitHub.

;;; Code:

(require 'ert)
(require 'gh-review)

;;; References

(ert-deftest gh-review-parse-reference-forms ()
  (should (equal (gh-review-parse-reference "https://github.com/o/r/pull/12")
                 '("o" "r" 12)))
  (should (equal (gh-review-parse-reference
                  "see https://github.com/nix-caisson/caisson-core/pull/7/files#diff-1 now")
                 '("nix-caisson" "caisson-core" 7)))
  (should (equal (gh-review-parse-reference "clhodapp/ch-emacs-config#51")
                 '("clhodapp" "ch-emacs-config" 51)))
  (should (equal (gh-review-parse-reference "(see a.b/c-d#3)") '("a.b" "c-d" 3)))
  (should-not (gh-review-parse-reference "https://github.com/o/r/issues/12"))
  (should-not (gh-review-parse-reference "no reference here"))
  (should-not (gh-review-parse-reference nil)))

;;; Diff parsing

(defconst gh-review-test--diff "\
diff --git a/lib/a.nix b/lib/a.nix
index 1111111111111111111111111111111111111111..2222222222222222222222222222222222222222 100644
--- a/lib/a.nix
+++ b/lib/a.nix
@@ -3 +3 @@ let
-  x = 1;
+  x = 2;
@@ -10,0 +11,2 @@ in
+  y = 3;
+  z = 4;
\\ No newline at end of file
diff --git a/new.txt b/new.txt
new file mode 100644
index 0000000000000000000000000000000000000000..3333333333333333333333333333333333333333
--- /dev/null
+++ b/new.txt
@@ -0,0 +1,2 @@
+one
+two
diff --git a/gone.txt b/gone.txt
deleted file mode 100644
index 4444444444444444444444444444444444444444..0000000000000000000000000000000000000000
--- a/gone.txt
+++ /dev/null
@@ -1 +0,0 @@
-bye
diff --git a/old name.txt b/new name.txt
similarity index 100%
rename from old name.txt
rename to new name.txt
diff --git a/img.png b/img.png
index 5555555555555555555555555555555555555555..6666666666666666666666666666666666666666 100644
Binary files a/img.png and b/img.png differ
diff --git a/run.sh b/run.sh
old mode 100644
new mode 100755
diff --git \"a/caf\\303\\251.txt\" \"b/caf\\303\\251.txt\"
index 7777777777777777777777777777777777777777..8888888888888888888888888888888888888888 100644
--- \"a/caf\\303\\251.txt\"
+++ \"b/caf\\303\\251.txt\"
@@ -1 +1 @@
-a
+b
"
  "A diff covering each kind of change the parser distinguishes.")

(ert-deftest gh-review-parse-diff-kinds ()
  (let* ((files (gh-review-parse-diff gh-review-test--diff))
         (by-path (lambda (path) (seq-find (lambda (f) (equal (gh-review-file-path f) path))
                                           files))))
    (should (equal (mapcar #'gh-review-file-path files)
                   '("lib/a.nix" "new.txt" "gone.txt" "new name.txt" "img.png"
                     "run.sh" "café.txt")))
    (let ((a (funcall by-path "lib/a.nix")))
      (should (eq (gh-review-file-status a) 'modified))
      (should (= (gh-review-file-additions a) 3))
      (should (= (gh-review-file-deletions a) 1))
      (should (equal (gh-review-file-new-blob a) "2222222222222222222222222222222222222222"))
      (should (equal (mapcar (lambda (h) (list (gh-review-hunk-old-start h)
                                               (gh-review-hunk-old-count h)
                                               (gh-review-hunk-new-start h)
                                               (gh-review-hunk-new-count h)))
                             (gh-review-file-hunks a))
                     '((3 1 3 1) (10 0 11 2))))
      (should (equal (gh-review-hunk-lines (cadr (gh-review-file-hunks a)))
                     '((add . "  y = 3;") (add . "  z = 4;")))))
    (let ((new (funcall by-path "new.txt")))
      (should (eq (gh-review-file-status new) 'added))
      (should-not (gh-review-file-old-blob new)))
    (let ((gone (funcall by-path "gone.txt")))
      (should (eq (gh-review-file-status gone) 'deleted))
      (should (equal (gh-review-file-path gone) "gone.txt"))
      (should-not (gh-review-file-new-blob gone)))
    (let ((renamed (funcall by-path "new name.txt")))
      (should (eq (gh-review-file-status renamed) 'renamed))
      (should (equal (gh-review-file-old-path renamed) "old name.txt"))
      (should-not (gh-review-file-hunks renamed)))
    (should (gh-review-file-binary (funcall by-path "img.png")))
    (let ((script (funcall by-path "run.sh")))
      (should (equal (gh-review-file-old-mode script) "100644"))
      (should (equal (gh-review-file-new-mode script) "100755")))
    (should (= (length (gh-review-file-hunks (funcall by-path "café.txt"))) 1))))

(ert-deftest gh-review-parse-cat-file-batch-sizes ()
  (let* ((text (encode-coding-string "é\nx" 'utf-8))
         (bytes (concat "aaaa blob " (number-to-string (length text)) "\n" text "\n"
                        "bbbb blob 0\n\n")))
    (should (equal (gh-review-parse-cat-file-batch bytes)
                   '(("aaaa" . "é\nx") ("bbbb" . ""))))))

;;; Line plans

(defun gh-review-test--file (total hunks)
  "A file of TOTAL new lines named Ln with HUNKS, a list of hunk specs.
Each spec is (OLD-START OLD-COUNT NEW-START NEW-COUNT)."
  (gh-review-file--create
   :path "f" :old-path "f" :status 'modified :additions 0 :deletions 0
   :new-lines (vconcat (mapcar (lambda (n) (format "L%d" n))
                               (number-sequence 1 total)))
   :old-lines []
   :hunks (mapcar (lambda (spec)
                    (gh-review-hunk--create
                     :old-start (nth 0 spec) :old-count (nth 1 spec)
                     :new-start (nth 2 spec) :new-count (nth 3 spec)
                     :lines (append (make-list (nth 1 spec) '(del . "old"))
                                    (make-list (nth 3 spec) '(add . "new")))))
                  hunks)))

(defun gh-review-test--shape (rows)
  "ROWS reduced to symbols and numbers for comparison."
  (mapcar (lambda (row)
            (pcase row
              (`(context ,old ,new ,_) (list 'c old new))
              (`(gap ,index ,hidden) (list 'gap index hidden))
              (`(,kind ,n ,_) (list kind n))))
          rows))

(ert-deftest gh-review-line-plan-gaps ()
  ;; 30 lines, line 15 replaced: 3 lines of context each side.
  (let ((file (gh-review-test--file 30 '((15 1 15 1)))))
    (should (equal (gh-review-test--shape (gh-review-line-plan file))
                   '((gap 0 11) (c 12 12) (c 13 13) (c 14 14)
                     (del 15) (add 15)
                     (c 16 16) (c 17 17) (c 18 18) (gap 1 12))))
    ;; Expanding the leading region by 20 shows all of it.
    (setf (gh-review-file-gaps file) '((0 . (0 . 23))))
    (should (equal (car (gh-review-test--shape (gh-review-line-plan file)))
                   '(c 1 1)))
    (setf (gh-review-file-gaps file) '((1 . all)))
    (should (equal (car (last (gh-review-test--shape (gh-review-line-plan file))))
                   '(c 30 30)))))

(ert-deftest gh-review-line-plan-offsets ()
  ;; Two lines inserted after line 5, so later lines shift by two.
  (let* ((file (gh-review-test--file 12 '((5 0 6 2))))
         (rows (gh-review-test--shape (gh-review-line-plan file))))
    (should (member '(add 6) rows))
    (should (member '(add 7) rows))
    (should (member '(c 6 8) rows))
    ;; Five leading lines with three shown would hide two, so all show.
    (should (equal (car rows) '(c 1 1)))))

(ert-deftest gh-review-line-plan-small-gap-merges ()
  ;; Eight unchanged lines between two changes: 3 + 3 shown and two
  ;; hidden, which is not worth a row, so all eight show.
  (let* ((file (gh-review-test--file 20 '((5 1 5 1) (14 1 14 1))))
         (rows (gh-review-test--shape (gh-review-line-plan file))))
    (should-not (seq-find (lambda (row) (and (eq (car row) 'gap) (= (cadr row) 1)))
                          rows))
    (should (member '(c 9 9) rows))))

(ert-deftest gh-review-line-plan-commentable ()
  (let* ((file (gh-review-test--file 30 '((15 1 15 1))))
         (rows (gh-review-line-plan file)))
    (setf (gh-review-file-gaps file) '((0 . all) (1 . all)))
    (setq rows (gh-review-line-plan file))
    (cl-flet ((commentable (n) (nth 3 (seq-find (lambda (row) (and (eq (car row) 'context)
                                                                  (= (nth 2 row) n)))
                                               rows))))
      (should (commentable 12))
      (should-not (commentable 11))
      (should (commentable 18))
      (should-not (commentable 19)))))

(ert-deftest gh-review-line-plan-deleted-file ()
  (let ((file (gh-review-file--create
               :path "g" :old-path "g" :status 'deleted
               :new-lines [] :old-lines ["a" "b"]
               :hunks (list (gh-review-hunk--create :old-start 1 :old-count 2
                                                    :new-start 0 :new-count 0
                                                    :lines '((del . "a") (del . "b")))))))
    (should (equal (gh-review-test--shape (gh-review-line-plan file))
                   '((del 1) (del 2))))))

(ert-deftest gh-review-map-line-sides ()
  ;; Lines 6-7 added after old line 5; old line 9 replaced by new 11.
  (let ((file (gh-review-test--file 20 '((5 0 6 2) (9 1 11 1)))))
    (should (= (gh-review-map-line file 3 'after) 3))
    (should (= (gh-review-map-line file 8 'after) 6))
    (should (= (gh-review-map-line file 6 'before) 8))
    (should (= (gh-review-map-line file 6 'after) 5))
    (should (= (gh-review-map-line file 15 'after) 13))
    (should (= (gh-review-map-line file 13 'before) 15))))

;;; The tree

(ert-deftest gh-review-tree-nodes-compress ()
  (let ((nodes (gh-review-tree-nodes
                (mapcar (lambda (path) (cons (split-string path "/") path))
                        '("a/b/c/x.el" "a/b/c/y.el" "a/z.el" "top.el")))))
    (should (equal nodes
                   '((dir "a" ((dir "b/c" ((file "x.el" "a/b/c/x.el")
                                           (file "y.el" "a/b/c/y.el")))
                               (file "z.el" "a/z.el")))
                     (file "top.el" "top.el"))))))

;;; Rendering

(defun gh-review-test--pr ()
  "A loaded pull request with one modified file, a thread and a draft."
  (let* ((file (gh-review-test--file 30 '((15 1 15 1))))
         (pr (gh-review-pr--create
              :owner "o" :repo "r" :number 1 :title "Title" :author "someone"
              :viewer "me" :state "OPEN" :base-ref "main" :head-ref "topic"
              :files (list file) :status 'ready
              :threads (list `((id . "T1") (isResolved) (isOutdated) (path . "f")
                               (line . 16) (diffSide . "RIGHT")
                               (comments (nodes ((author (login . "rev"))
                                                 (body . "why this?")
                                                 (createdAt . "2026-10-01T00:00:00Z"))))))
              :drafts (list '(:path "f" :side "RIGHT" :line 15 :body "pending note")))))
    (setf (gh-review-file-old-lines file) (gh-review-file-new-lines file))
    pr))

(defmacro gh-review-test--with-diff (pr &rest body)
  "Render PR into a temporary diff buffer and run BODY there."
  (declare (indent 1))
  `(with-temp-buffer
     (gh-review-diff-mode)
     (setq gh-review-buffer-pr ,pr)
     (let ((gh-review-fontify nil))
       (gh-review-render)
       ,@body)))

(ert-deftest gh-review-render-anchors ()
  (gh-review-test--with-diff (gh-review-test--pr)
    (let ((text (buffer-string)))
      (should (string-search "Title" text))
      (should (string-search "11 hidden lines" text))
      (should (string-search "why this?" text))
      (should (string-search "pending note" text))
      ;; The thread sits right after its line.
      (should (string-match-p "L16\n.*rev" text))
      (should (string-match-p "L15\n.*Pending comment" text)))))

(ert-deftest gh-review-render-copy-drops-gutter ()
  (gh-review-test--with-diff (gh-review-test--pr)
    (goto-char (point-min))
    (search-forward "L13")
    (should (equal (filter-buffer-substring (line-beginning-position) (line-end-position))
                   "L13"))))

(ert-deftest gh-review-render-expand-keeps-point ()
  (gh-review-test--with-diff (gh-review-test--pr)
    (goto-char (point-min))
    (search-forward "L14")
    (let ((line (gh-review-line-at-point)))
      (goto-char (point-min))
      (search-forward "hidden lines")
      (gh-review-expand-more t)
      (should-not (string-search "11 hidden lines" (buffer-string)))
      (should (string-search "L1\n" (buffer-string)))
      (gh-review--restore-position (list 'line "f" "RIGHT" (plist-get line :line)))
      (should (equal (plist-get (gh-review-line-at-point) :new) 14)))))

(ert-deftest gh-review-render-annotations ()
  (let ((gh-review-annotation-functions
         (list (lambda (_pr)
                 (list '(:path "f" :side "RIGHT" :line 18 :heading "Blocker" :body "fix")
                       '(:heading "Verdict" :body "safe"))))))
    (gh-review-test--with-diff (gh-review-test--pr)
      (should (string-match-p "L18\n.*Blocker" (buffer-string)))
      (goto-char (point-min))
      (should (search-forward "Verdict" nil t))
      (should (equal (plist-get (gh-review-annotation-at-point) :body) "safe")))))

(ert-deftest gh-review-render-fold ()
  (gh-review-test--with-diff (gh-review-test--pr)
    (goto-char (point-min))
    (search-forward "▾")
    (gh-review-toggle)
    (should (gh-review-file-collapsed (car (gh-review-pr-files gh-review-buffer-pr))))
    (should (string-search "▸" (buffer-string)))))

;;; Git round trip

(defun gh-review-test--git (directory &rest args)
  "Run git ARGS in DIRECTORY, failing the test on error."
  (let ((default-directory directory))
    (with-temp-buffer
      (unless (eql 0 (apply #'call-process "git" nil t nil
                            "-c" "user.name=t" "-c" "user.email=t@t" args))
        (error "git %s: %s" (car args) (buffer-string)))
      (string-trim (buffer-string)))))

(ert-deftest gh-review-fetch-from-local-remote ()
  (let* ((root (make-temp-file "gh-review-test" t))
         (work (expand-file-name "work" root))
         (gh-review-cache-directory (expand-file-name "cache/" root))
         (gh-review-remote-url-function (lambda (_) (concat "file://" work))))
    (make-directory work)
    (gh-review-test--git work "init" "-q" "-b" "main")
    (gh-review-test--git work "config" "uploadpack.allowFilter" "true")
    (gh-review-test--git work "config" "uploadpack.allowAnySHA1InWant" "true")
    (with-temp-file (expand-file-name "a.txt" work)
      (insert (mapconcat (lambda (n) (format "line %d" n)) (number-sequence 1 20) "\n") "\n"))
    (gh-review-test--git work "add" ".")
    (gh-review-test--git work "commit" "-q" "-m" "base")
    (let ((base (gh-review-test--git work "rev-parse" "HEAD")))
      (gh-review-test--git work "checkout" "-q" "-b" "topic")
      (with-temp-file (expand-file-name "a.txt" work)
        (insert (mapconcat (lambda (n) (if (= n 10) "changed" (format "line %d" n)))
                           (number-sequence 1 20) "\n")
                "\n"))
      (with-temp-file (expand-file-name "b.txt" work) (insert "new\n"))
      (gh-review-test--git work "add" ".")
      (gh-review-test--git work "commit" "-q" "-m" "topic")
      (gh-review-test--git work "update-ref" "refs/pull/1/head" "HEAD")
      (let ((pr (gh-review-pr--create :owner "o" :repo "r" :number 1
                                      :merge-base base))
            (done nil) (failure nil))
        (gh-review--fetch-commits
         pr
         (lambda ()
           (gh-review--fetch-diff
            pr
            (lambda ()
              (gh-review--read-blobs pr (lambda () (setq done t))
                                     (lambda (m) (setq failure m done t))))
            (lambda (m) (setq failure m done t))))
         (lambda (m) (setq failure m done t)))
        (while (not done) (accept-process-output nil 0.05))
        (should-not failure)
        (should (equal (mapcar #'gh-review-file-path (gh-review-pr-files pr))
                       '("a.txt" "b.txt")))
        (let ((a (gh-review-pr-file pr "a.txt")))
          (should (equal (aref (gh-review-file-new-lines a) 9) "changed"))
          (should (equal (aref (gh-review-file-old-lines a) 9) "line 10")))
        (should (equal (gh-review-all-paths pr) '("a.txt" "b.txt")))
        (should (equal (gh-review-file-contents pr "a.txt" 'before)
                       (with-temp-buffer
                         (insert (mapconcat (lambda (n) (format "line %d" n))
                                            (number-sequence 1 20) "\n")
                                 "\n")
                         (buffer-string))))
        (should (string-search "+changed" (gh-review-diff-text pr '("a.txt"))))))
    (delete-directory root t)))

;;; gh-review-ert.el ends here
