;;; gh-review-core.el --- Pull request model and fetching for gh-review -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; The data side of gh-review: parsing a pull request reference, the
;; pull request record, fetching metadata from GitHub through the `gh'
;; CLI, and fetching the two commits the diff compares into a local
;; cache repository so that diffs, whole files and file listings are
;; read from git rather than from the API.
;;
;; The diff GitHub shows for a pull request compares the merge base of
;; the base branch and the head with the head.  The cache repository
;; holds exactly those two commits, fetched at depth 1 without blobs;
;; git fetches the blobs a diff or a file view needs when it first
;; reads them.  That keeps the first fetch small even for a repository
;; with a long history.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)

(defgroup gh-review nil
  "Review GitHub pull requests."
  :group 'tools
  :prefix "gh-review-")

(defcustom gh-review-gh-program "gh"
  "The GitHub CLI program."
  :type 'string)

(defcustom gh-review-git-program "git"
  "The git program."
  :type 'string)

(defcustom gh-review-cache-directory
  (expand-file-name "gh-review/" (or (getenv "XDG_CACHE_HOME") "~/.cache"))
  "Directory holding the cache repositories, worktrees and drafts."
  :type 'directory)

(defcustom gh-review-host "github.com"
  "The GitHub host pull request links are recognized for."
  :type 'string)

;;; Pull request references

(defun gh-review-parse-reference (string)
  "Parse STRING as a pull request reference.
Return (OWNER REPO NUMBER) or nil.  STRING may be a pull request URL
on `gh-review-host', with or without a trailing tab path such as
/files, or the short form OWNER/REPO#NUMBER.  The first reference in
STRING is used, so a link surrounded by other text also parses."
  (when (stringp string)
    (let ((case-fold-search t))
      (cond
       ((string-match
         (concat "https?://" (regexp-quote gh-review-host)
                 "/\\([A-Za-z0-9_.-]+\\)/\\([A-Za-z0-9_.-]+\\)/pull/\\([0-9]+\\)")
         string)
        (list (match-string 1 string) (match-string 2 string)
              (string-to-number (match-string 3 string))))
       ((string-match
         "\\(?:\\`\\|[^A-Za-z0-9_./-]\\)\\([A-Za-z0-9_.-]+\\)/\\([A-Za-z0-9_.-]+\\)#\\([0-9]+\\)"
         string)
        (list (match-string 1 string) (match-string 2 string)
              (string-to-number (match-string 3 string))))))))

;;; The pull request record

(cl-defstruct (gh-review-pr (:constructor gh-review-pr--create)
                            (:copier nil))
  "A pull request under review.
The metadata slots hold what GitHub reported at the last fetch.
BASE-OID is the tip of the base branch and MERGE-BASE the commit the
diff compares the head with.  FILES holds `gh-review-file' records in
diff order."
  owner repo number
  id url title body body-html state draft author viewer
  base-ref head-ref base-oid head-oid head-repo maintainer-can-modify
  merge-base mergeable review-decision additions deletions
  merge-methods checks comments reviews threads viewed
  files all-paths drafts
  (status 'new) error
  ;; Free-form properties other packages attach to the pull request.
  plist)

(cl-defstruct (gh-review-file (:constructor gh-review-file--create)
                              (:copier nil))
  "One changed file of a pull request.
STATUS is one of the symbols added, deleted, modified, renamed or
copied.  HUNKS is a list of `gh-review-hunk' records parsed from a
diff with no context lines.  OLD-BLOB and NEW-BLOB are object ids or
nil when that side does not exist.  OLD-LINES and NEW-LINES are
vectors of the side's lines, filled when the contents are read.
COLLAPSED and GAPS are display state: whether the file is folded,
and how far each unchanged region has been expanded."
  path old-path status binary
  old-blob new-blob old-mode new-mode
  hunks additions deletions
  old-lines new-lines
  collapsed gaps)

(cl-defstruct (gh-review-hunk (:constructor gh-review-hunk--create)
                              (:copier nil))
  "A run of changed lines.
OLD-START and NEW-START follow unified diff conventions: for a side
with a count of zero the start is the line before the change.  LINES
is a list of (KIND . TEXT) with KIND `del' or `add'."
  old-start old-count new-start new-count lines)

(defun gh-review-pr-key (pr)
  "The OWNER/REPO#NUMBER string naming PR."
  (format "%s/%s#%d" (gh-review-pr-owner pr) (gh-review-pr-repo pr)
          (gh-review-pr-number pr)))

(defun gh-review-pr-name-with-owner (pr)
  "The OWNER/REPO string of PR's base repository."
  (format "%s/%s" (gh-review-pr-owner pr) (gh-review-pr-repo pr)))

(defun gh-review-pr-viewer-authored-p (pr)
  "Whether the signed-in user wrote PR."
  (and (gh-review-pr-viewer pr)
       (equal (gh-review-pr-viewer pr) (gh-review-pr-author pr))))

(defun gh-review-pr-get (pr property)
  "Value of PROPERTY in PR's free-form property list."
  (plist-get (gh-review-pr-plist pr) property))

(defun gh-review-pr-put (pr property value)
  "Set PROPERTY to VALUE in PR's free-form property list."
  (setf (gh-review-pr-plist pr)
        (plist-put (gh-review-pr-plist pr) property value)))

(defun gh-review-pr-file (pr path)
  "The changed file of PR at PATH, or nil."
  (seq-find (lambda (file) (equal (gh-review-file-path file) path))
            (gh-review-pr-files pr)))

(defvar gh-review--prs (make-hash-table :test #'equal)
  "Open pull requests keyed by `gh-review-pr-key'.")

(defvar-local gh-review-buffer-pr nil
  "The pull request a gh-review buffer shows.")

(defun gh-review-current-pr (&optional noerror)
  "The pull request of the current buffer.
Signal a user error when there is none, unless NOERROR."
  (or gh-review-buffer-pr
      (unless noerror
        (user-error "Not in a gh-review buffer"))))

(defun gh-review-pr-for (owner repo number)
  "The pull request record for OWNER/REPO#NUMBER, created when absent."
  (let ((key (format "%s/%s#%d" owner repo number)))
    (or (gethash key gh-review--prs)
        (puthash key (gh-review-pr--create :owner owner :repo repo
                                           :number number)
                 gh-review--prs))))

;;; Processes

(defun gh-review--start (name command callback &rest options)
  "Run COMMAND, a list of strings, asynchronously as process NAME.
CALLBACK receives the exit status, the standard output and the
standard error once the process ends.  OPTIONS is a plist: :input
is a string written to standard input, :directory the working
directory, :coding the coding system for output (utf-8 by default)."
  (let* ((default-directory (or (plist-get options :directory)
                                default-directory))
         (out (generate-new-buffer (format " *%s*" name)))
         (err (generate-new-buffer (format " *%s stderr*" name)))
         (err-pipe (make-pipe-process :name (concat name "-stderr")
                                      :buffer err :noquery t
                                      :sentinel #'ignore))
         (process
          (make-process
           :name name :buffer out :stderr err-pipe :noquery t
           :connection-type 'pipe
           :coding (or (plist-get options :coding) 'utf-8)
           :command command
           :sentinel
           (lambda (process _event)
             (unless (process-live-p process)
               ;; Drain whatever the stderr pipe still holds before
               ;; its buffer is read.
               (while (accept-process-output err-pipe 0.01))
               (let ((status (process-exit-status process))
                     (stdout (with-current-buffer out (buffer-string)))
                     (stderr (with-current-buffer err (buffer-string))))
                 (delete-process err-pipe)
                 (kill-buffer out)
                 (kill-buffer err)
                 (funcall callback status stdout stderr)))))))
    (when-let* ((input (plist-get options :input)))
      (process-send-string process input))
    (process-send-eof process)
    process))

(defun gh-review--call (program &rest args)
  "Run PROGRAM with ARGS synchronously and return its standard output.
Signal an error carrying the standard error when it exits non-zero."
  (let ((errfile (make-temp-file "gh-review-err")))
    (unwind-protect
        (with-temp-buffer
          (let ((status (apply #'call-process program nil
                               (list t errfile) nil args)))
            (unless (eql status 0)
              (error "%s %s failed: %s" program (car args)
                     (string-trim
                      (with-temp-buffer
                        (insert-file-contents errfile)
                        (buffer-string)))))
            (buffer-string)))
      (delete-file errfile))))

(defun gh-review--git-args (directory &rest args)
  "Argument list running git ARGS in the git directory DIRECTORY.
The credential helper is `gh', so private repositories fetch with
the same login the API calls use, whatever the user's git
configuration says."
  (append (list "--git-dir" (expand-file-name directory)
                "-c" "core.quotePath=false"
                "-c" "credential.helper="
                "-c" (format "credential.helper=!%s auth git-credential"
                             (shell-quote-argument gh-review-gh-program)))
          args))

(defun gh-review--git (directory &rest args)
  "Run git ARGS in git directory DIRECTORY synchronously; return stdout."
  (apply #'gh-review--call gh-review-git-program
         (apply #'gh-review--git-args directory args)))

(defun gh-review--git-async (directory args callback &rest options)
  "Run git ARGS in git directory DIRECTORY; see `gh-review--start'.
CALLBACK receives the standard output on success.  A failure is
reported through the :error option, a function of the message, or
signalled when there is none."
  (let ((on-error (plist-get options :error)))
    (apply #'gh-review--start "gh-review-git"
           (cons gh-review-git-program
                 (apply #'gh-review--git-args directory args))
           (lambda (status stdout stderr)
             (if (eql status 0)
                 (funcall callback stdout)
               (let ((message (format "git %s failed: %s"
                                      (car args) (string-trim stderr))))
                 (if on-error
                     (funcall on-error message)
                   (error "%s" message)))))
           options)))

(defun gh-review--json (string)
  "Parse STRING as JSON into alists and lists, null and false as nil."
  (json-parse-string string :object-type 'alist :array-type 'list
                     :null-object nil :false-object nil))

(defun gh-review--gh-async (args callback &rest options)
  "Run gh ARGS asynchronously; CALLBACK receives the parsed JSON output.
OPTIONS are those of `gh-review--git-async', plus :raw, under which
CALLBACK receives the output string unparsed."
  (let ((on-error (plist-get options :error))
        (raw (plist-get options :raw)))
    (apply #'gh-review--start "gh-review-gh"
           (cons gh-review-gh-program args)
           (lambda (status stdout stderr)
             (if (eql status 0)
                 (funcall callback
                          (if (or raw (string-blank-p stdout))
                              stdout
                            (gh-review--json stdout)))
               (let ((message (format "gh %s failed: %s"
                                      (string-join (seq-take args 2) " ")
                                      (string-trim
                                       (if (string-blank-p stderr)
                                           stdout
                                         stderr)))))
                 (if on-error
                     (funcall on-error message)
                   (error "%s" message)))))
           options)))

;;; GitHub metadata

(defconst gh-review--query "
query($owner: String!, $name: String!, $number: Int!) {
  viewer { login }
  repository(owner: $owner, name: $name) {
    mergeCommitAllowed squashMergeAllowed rebaseMergeAllowed
    pullRequest(number: $number) {
      id url title body bodyHTML state isDraft
      author { login }
      baseRefName headRefName baseRefOid headRefOid
      headRepository { nameWithOwner }
      maintainerCanModify mergeable reviewDecision
      additions deletions
      files(first: 100) { nodes { path viewerViewedState } }
      commits(last: 1) { nodes { commit { statusCheckRollup {
        state
        contexts(first: 100) { nodes {
          __typename
          ... on CheckRun { name conclusion status detailsUrl }
          ... on StatusContext { context state targetUrl }
        } }
      } } } }
      comments(first: 100) { nodes {
        id author { login } body bodyHTML createdAt url
      } }
      reviews(first: 100) { nodes {
        id author { login } state body bodyHTML submittedAt url
      } }
      reviewThreads(first: 100) { nodes {
        id isResolved isOutdated path line startLine
        originalLine diffSide startDiffSide
        comments(first: 100) { nodes {
          id databaseId author { login } body createdAt url
        } }
      } }
    }
  }
}"
  "The GraphQL query for everything gh-review shows about a pull request.")

(defun gh-review--nodes (alist &rest path)
  "The nodes list under the PATH of keys into ALIST."
  (alist-get 'nodes (apply #'gh-review--dig alist path)))

(defun gh-review--dig (alist &rest path)
  "Follow the keys of PATH into nested ALIST."
  (let ((value alist))
    (dolist (key path value)
      (setq value (alist-get key value)))))

(defun gh-review--check-entry (node)
  "A plist describing the status check NODE."
  (if (equal (alist-get '__typename node) "CheckRun")
      (list :name (alist-get 'name node)
            :state (or (alist-get 'conclusion node)
                       (alist-get 'status node))
            :url (alist-get 'detailsUrl node))
    (list :name (alist-get 'context node)
          :state (alist-get 'state node)
          :url (alist-get 'targetUrl node))))

(defun gh-review--apply-metadata (pr data)
  "Store the GraphQL response DATA in PR."
  (let* ((repository (gh-review--dig data 'data 'repository))
         (node (alist-get 'pullRequest repository))
         (rollup (gh-review--dig
                  (car (gh-review--nodes node 'commits))
                  'commit 'statusCheckRollup)))
    (unless node
      (error "No pull request %s" (gh-review-pr-key pr)))
    (setf (gh-review-pr-viewer pr) (gh-review--dig data 'data 'viewer 'login)
          (gh-review-pr-id pr) (alist-get 'id node)
          (gh-review-pr-url pr) (alist-get 'url node)
          (gh-review-pr-title pr) (alist-get 'title node)
          (gh-review-pr-body pr) (alist-get 'body node)
          (gh-review-pr-body-html pr) (alist-get 'bodyHTML node)
          (gh-review-pr-state pr) (alist-get 'state node)
          (gh-review-pr-draft pr) (alist-get 'isDraft node)
          (gh-review-pr-author pr) (gh-review--dig node 'author 'login)
          (gh-review-pr-base-ref pr) (alist-get 'baseRefName node)
          (gh-review-pr-head-ref pr) (alist-get 'headRefName node)
          (gh-review-pr-base-oid pr) (alist-get 'baseRefOid node)
          (gh-review-pr-head-oid pr) (alist-get 'headRefOid node)
          (gh-review-pr-head-repo pr) (gh-review--dig
                                       node 'headRepository 'nameWithOwner)
          (gh-review-pr-maintainer-can-modify pr)
          (alist-get 'maintainerCanModify node)
          (gh-review-pr-mergeable pr) (alist-get 'mergeable node)
          (gh-review-pr-review-decision pr) (alist-get 'reviewDecision node)
          (gh-review-pr-additions pr) (alist-get 'additions node)
          (gh-review-pr-deletions pr) (alist-get 'deletions node)
          (gh-review-pr-merge-methods pr)
          (delq nil (list (and (alist-get 'mergeCommitAllowed repository)
                               'merge)
                          (and (alist-get 'squashMergeAllowed repository)
                               'squash)
                          (and (alist-get 'rebaseMergeAllowed repository)
                               'rebase)))
          (gh-review-pr-checks pr)
          (list :state (alist-get 'state rollup)
                :contexts (mapcar #'gh-review--check-entry
                                  (gh-review--nodes rollup 'contexts)))
          (gh-review-pr-comments pr) (gh-review--nodes node 'comments)
          (gh-review-pr-reviews pr) (gh-review--nodes node 'reviews)
          (gh-review-pr-threads pr) (gh-review--nodes node 'reviewThreads)
          (gh-review-pr-viewed pr)
          (mapcar (lambda (file)
                    (cons (alist-get 'path file)
                          (equal (alist-get 'viewerViewedState file)
                                 "VIEWED")))
                  (gh-review--nodes node 'files)))))

(defun gh-review--fetch-metadata (pr callback on-error)
  "Fetch PR's metadata from GitHub, then call CALLBACK.
ON-ERROR receives a message when the request fails."
  (gh-review--gh-async
   (list "api" "graphql"
         "-f" (concat "query=" gh-review--query)
         "-f" (concat "owner=" (gh-review-pr-owner pr))
         "-f" (concat "name=" (gh-review-pr-repo pr))
         "-F" (format "number=%d" (gh-review-pr-number pr)))
   (lambda (data)
     (condition-case err
         (progn (gh-review--apply-metadata pr data)
                (funcall callback))
       (error (funcall on-error (error-message-string err)))))
   :error on-error))

(defun gh-review--fetch-merge-base (pr callback on-error)
  "Ask GitHub for PR's merge base, store it, then call CALLBACK.
ON-ERROR receives a message when the request fails."
  (gh-review--gh-async
   (list "api"
         (format "repos/%s/compare/%s...%s"
                 (gh-review-pr-name-with-owner pr)
                 (gh-review-pr-base-oid pr)
                 (gh-review-pr-head-oid pr))
         "--jq" ".merge_base_commit.sha")
   (lambda (output)
     (setf (gh-review-pr-merge-base pr) (string-trim output))
     (funcall callback))
   :error on-error :raw t))

;;; The cache repository

(defun gh-review-git-directory (pr)
  "The cache repository holding PR's commits."
  (expand-file-name (format "repos/%s/%s.git" (gh-review-pr-owner pr)
                            (gh-review-pr-repo pr))
                    gh-review-cache-directory))

(defvar gh-review-remote-url-function #'gh-review--remote-url
  "Function of a pull request returning the URL its commits fetch from.")

(defun gh-review--remote-url (pr)
  "The HTTPS clone URL of PR's base repository."
  (format "https://%s/%s.git" gh-review-host (gh-review-pr-name-with-owner pr)))

(defun gh-review--ensure-repository (pr)
  "Create PR's cache repository when it does not exist yet.
The repository is a partial clone without blobs: its remote is a
promisor, so git fetches a missing blob on first read."
  (let ((directory (gh-review-git-directory pr)))
    (unless (file-exists-p (expand-file-name "HEAD" directory))
      (make-directory directory t)
      (gh-review--call gh-review-git-program "init" "--bare" "-q" directory)
      (gh-review--git directory "remote" "add" "origin"
                      (funcall gh-review-remote-url-function pr))
      (gh-review--git directory "config" "remote.origin.promisor" "true")
      (gh-review--git directory "config"
                      "remote.origin.partialclonefilter" "blob:none"))
    directory))

(defun gh-review--head-ref (pr)
  "The ref the cache repository keeps PR's head under."
  (format "refs/gh-review/pull/%d/head" (gh-review-pr-number pr)))

(defun gh-review--fetch-commits (pr callback on-error)
  "Fetch PR's merge base and head into the cache, then call CALLBACK.
ON-ERROR receives a message when the fetch fails."
  (let ((directory (gh-review--ensure-repository pr)))
    (gh-review--git-async
     directory
     (list "fetch" "-q" "--no-tags" "--depth=1" "--filter=blob:none"
           "origin"
           (gh-review-pr-merge-base pr)
           (format "+refs/pull/%d/head:%s" (gh-review-pr-number pr)
                   (gh-review--head-ref pr)))
     (lambda (_)
       ;; The head may have moved between the metadata request and the
       ;; fetch; the fetched commit is the one the diff shows.
       (setf (gh-review-pr-head-oid pr)
             (string-trim (gh-review--git directory "rev-parse"
                                          (gh-review--head-ref pr))))
       (funcall callback))
     :error on-error)))

;;; Parsing diffs

(defun gh-review--unquote-path (path)
  "PATH with git's C-style quoting removed, when it is quoted."
  (if (string-prefix-p "\"" path)
      (decode-coding-string
       (let ((string (read path)))
         (if (multibyte-string-p string)
             (encode-coding-string string 'utf-8)
           string))
       'utf-8)
    path))

(defun gh-review--strip-side (path)
  "PATH from a ---/+++ line without its a/ or b/ prefix, or nil."
  (let ((path (gh-review--unquote-path
               (string-trim-right path "\t.*"))))
    (cond ((equal path "/dev/null") nil)
          ((string-match "\\`[ab]/" path) (substring path 2))
          (t path))))

(defun gh-review--git-header-paths (line)
  "Old and new path from a `diff --git a/X b/Y' LINE, as a cons.
Used only when the patch has no ---/+++ or rename lines, in which
case both paths are equal, so the line splits at its midpoint."
  (let* ((rest (substring line (length "diff --git ")))
         (half (/ (1- (length rest)) 2))
         (old (substring rest 0 half)))
    (cons (gh-review--strip-side old) (gh-review--strip-side old))))

(defun gh-review-parse-diff (text)
  "Parse the unified diff TEXT into a list of `gh-review-file' records.
TEXT comes from git diff with --full-index and no context lines."
  (let ((files nil) (file nil) (hunk nil))
    (cl-flet ((finish-hunk ()
                (when hunk
                  (setf (gh-review-hunk-lines hunk)
                        (nreverse (gh-review-hunk-lines hunk)))
                  (push hunk (gh-review-file-hunks file))
                  (setq hunk nil)))
              (finish-file ()
                (when file
                  (setf (gh-review-file-hunks file)
                        (nreverse (gh-review-file-hunks file)))
                  (unless (gh-review-file-path file)
                    (setf (gh-review-file-path file)
                          (gh-review-file-old-path file)))
                  (unless (gh-review-file-old-path file)
                    (setf (gh-review-file-old-path file)
                          (gh-review-file-path file)))
                  (push file files))))
      (dolist (line (split-string text "\n"))
        (cond
         ((string-prefix-p "diff --git " line)
          (finish-hunk)
          (finish-file)
          (let ((paths (gh-review--git-header-paths line)))
            (setq file (gh-review-file--create
                        :status 'modified :additions 0 :deletions 0
                        :path (cdr paths) :old-path (car paths)))))
         ((null file))
         (hunk
          (cond
           ((string-prefix-p "+" line)
            (push (cons 'add (substring line 1)) (gh-review-hunk-lines hunk))
            (cl-incf (gh-review-file-additions file)))
           ((string-prefix-p "-" line)
            (push (cons 'del (substring line 1)) (gh-review-hunk-lines hunk))
            (cl-incf (gh-review-file-deletions file)))
           ((string-prefix-p "\\" line))
           ((string-prefix-p "@@" line)
            (finish-hunk)
            (setq hunk (gh-review--parse-hunk-header line)))
           (t (finish-hunk))))
         ((string-prefix-p "@@" line)
          (setq hunk (gh-review--parse-hunk-header line)))
         ((string-prefix-p "new file mode " line)
          (setf (gh-review-file-status file) 'added
                (gh-review-file-new-mode file) (substring line 14)))
         ((string-prefix-p "deleted file mode " line)
          (setf (gh-review-file-status file) 'deleted
                (gh-review-file-old-mode file) (substring line 18)))
         ((string-prefix-p "old mode " line)
          (setf (gh-review-file-old-mode file) (substring line 9)))
         ((string-prefix-p "new mode " line)
          (setf (gh-review-file-new-mode file) (substring line 9)))
         ((string-prefix-p "rename from " line)
          (setf (gh-review-file-status file) 'renamed
                (gh-review-file-old-path file)
                (gh-review--unquote-path (substring line 12))))
         ((string-prefix-p "rename to " line)
          (setf (gh-review-file-path file)
                (gh-review--unquote-path (substring line 10))))
         ((string-prefix-p "copy from " line)
          (setf (gh-review-file-status file) 'copied
                (gh-review-file-old-path file)
                (gh-review--unquote-path (substring line 10))))
         ((string-prefix-p "copy to " line)
          (setf (gh-review-file-path file)
                (gh-review--unquote-path (substring line 8))))
         ((string-match "\\`index \\([0-9a-f]+\\)\\.\\.\\([0-9a-f]+\\)" line)
          (let ((old (match-string 1 line))
                (new (match-string 2 line)))
            (setf (gh-review-file-old-blob file)
                  (unless (string-match-p "\\`0+\\'" old) old)
                  (gh-review-file-new-blob file)
                  (unless (string-match-p "\\`0+\\'" new) new))))
         ((string-prefix-p "--- " line)
          (when-let* ((path (gh-review--strip-side (substring line 4))))
            (setf (gh-review-file-old-path file) path)))
         ((string-prefix-p "+++ " line)
          (when-let* ((path (gh-review--strip-side (substring line 4))))
            (setf (gh-review-file-path file) path)))
         ((string-prefix-p "Binary files " line)
          (setf (gh-review-file-binary file) t))))
      (finish-hunk)
      (finish-file))
    (nreverse files)))

(defun gh-review--parse-hunk-header (line)
  "A new `gh-review-hunk' from the @@ header LINE."
  (unless (string-match
           "\\`@@ -\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? \\+\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? @@"
           line)
    (error "Unparseable hunk header: %s" line))
  (cl-flet ((number (n default)
              (if (match-string n line)
                  (string-to-number (match-string n line))
                default)))
    (gh-review-hunk--create :old-start (number 1 0) :old-count (number 2 1)
                            :new-start (number 3 0) :new-count (number 4 1)
                            :lines nil)))

(defun gh-review--fetch-diff (pr callback on-error)
  "Diff PR's merge base with its head, store the files, call CALLBACK.
ON-ERROR receives a message when git fails."
  (gh-review--git-async
   (gh-review-git-directory pr)
   (list "diff" "--no-color" "--no-ext-diff" "--full-index" "-U0"
         "--find-renames" (gh-review-pr-merge-base pr)
         (gh-review-pr-head-oid pr))
   (lambda (output)
     (let ((previous (gh-review-pr-files pr))
           (files (gh-review-parse-diff output)))
       ;; Folding and expansion survive a refresh of the same file.
       (dolist (file files)
         (when-let* ((old (seq-find (lambda (f)
                                      (equal (gh-review-file-path f)
                                             (gh-review-file-path file)))
                                    previous)))
           (setf (gh-review-file-collapsed file) (gh-review-file-collapsed old)
                 (gh-review-file-gaps file) (gh-review-file-gaps old))))
       (setf (gh-review-pr-files pr) files)
       (funcall callback)))
   :error on-error))

;;; File contents

(defun gh-review--split-lines (text)
  "TEXT as a vector of lines, without the empty line after a final newline."
  (let ((lines (split-string text "\n")))
    (when (and lines (equal (car (last lines)) ""))
      (setq lines (butlast lines)))
    (vconcat lines)))

(defun gh-review-parse-cat-file-batch (bytes)
  "Parse `git cat-file --batch' output BYTES, a unibyte string.
Return an alist of (OID . TEXT) with TEXT decoded as UTF-8."
  (let ((position 0) (result nil))
    (while (string-match "\\([0-9a-f]+\\) \\([a-z]+\\) \\([0-9]+\\)\n"
                         bytes position)
      (let* ((oid (match-string 1 bytes))
             (size (string-to-number (match-string 3 bytes)))
             (start (match-end 0)))
        (push (cons oid (decode-coding-string
                         (substring bytes start (+ start size)) 'utf-8))
              result)
        (setq position (+ start size 1))))
    (nreverse result)))

(defun gh-review--read-blobs (pr callback on-error)
  "Read the contents of every changed text file of PR, then CALLBACK.
ON-ERROR receives a message when git fails."
  (let* ((files (seq-remove #'gh-review-file-binary (gh-review-pr-files pr)))
         (oids (delete-dups
                (delq nil (mapcan (lambda (file)
                                    (list (gh-review-file-old-blob file)
                                          (gh-review-file-new-blob file)))
                                  files)))))
    (if (null oids)
        (funcall callback)
      (gh-review--git-async
       (gh-review-git-directory pr)
       (list "cat-file" "--batch")
       (lambda (output)
         (let ((blobs (gh-review-parse-cat-file-batch output)))
           (dolist (file files)
             (setf (gh-review-file-old-lines file)
                   (gh-review--split-lines
                    (or (cdr (assoc (gh-review-file-old-blob file) blobs)) ""))
                   (gh-review-file-new-lines file)
                   (gh-review--split-lines
                    (or (cdr (assoc (gh-review-file-new-blob file) blobs)) ""))))
           (funcall callback)))
       :error on-error
       :coding 'binary
       :input (concat (string-join oids "\n") "\n")))))

(defun gh-review-file-contents (pr path side)
  "Contents of PATH in PR as a string.
SIDE is `before' for the merge base or `after' for the head."
  (gh-review--git (gh-review-git-directory pr) "show"
                  (format "%s:%s"
                          (if (eq side 'before)
                              (gh-review-pr-merge-base pr)
                            (gh-review-pr-head-oid pr))
                          path)))

(defun gh-review-all-paths (pr)
  "Every file path in PR's head, sorted; cached on PR."
  (or (gh-review-pr-all-paths pr)
      (setf (gh-review-pr-all-paths pr)
            (sort (split-string
                   (gh-review--git (gh-review-git-directory pr) "ls-tree"
                                   "-r" "--name-only"
                                   (gh-review-pr-head-oid pr))
                   "\n" t)
                  #'string<))))

(defun gh-review-diff-text (pr &optional paths context)
  "The unified diff of PR as GitHub shows it, as a string.
PATHS limits it to those files.  CONTEXT is the number of context
lines, 3 by default."
  (apply #'gh-review--git (gh-review-git-directory pr)
         "diff" "--no-color" "--no-ext-diff" "--find-renames"
         (format "-U%d" (or context 3))
         (gh-review-pr-merge-base pr) (gh-review-pr-head-oid pr)
         (when paths (cons "--" paths))))

;;; Worktrees

(defun gh-review-worktree-directory (pr)
  "Directory of PR's detached worktree at its head."
  (expand-file-name (format "worktrees/%s/%s/%d" (gh-review-pr-owner pr)
                            (gh-review-pr-repo pr) (gh-review-pr-number pr))
                    gh-review-cache-directory))

(defun gh-review-worktree (pr callback &optional on-error)
  "Check PR's head out into its worktree, then call CALLBACK with it.
An existing worktree is moved to the current head.  ON-ERROR
receives a message when git fails."
  (let ((directory (gh-review-worktree-directory pr))
        (git (gh-review-git-directory pr))
        (on-error (or on-error (lambda (message) (error "%s" message)))))
    (if (file-exists-p (expand-file-name ".git" directory))
        (gh-review--start
         "gh-review-worktree"
         (list gh-review-git-program "-C" directory
               "checkout" "-q" "--detach" "--force"
               (gh-review-pr-head-oid pr))
         (lambda (status _stdout stderr)
           (if (eql status 0)
               (funcall callback directory)
             (funcall on-error stderr))))
      (make-directory (file-name-directory directory) t)
      (gh-review--git-async
       git (list "worktree" "add" "-q" "--detach" "--force" directory
                 (gh-review-pr-head-oid pr))
       (lambda (_) (funcall callback directory))
       :error on-error))))

;;; Fetching everything

(defvar gh-review-after-fetch-hook nil
  "Hook run with the pull request after every successful fetch.")

(defun gh-review-fetch (pr callback)
  "Fetch everything about PR, then call CALLBACK with PR.
Metadata comes from GitHub; the merge base and head go into the
cache repository, the diff and file contents come from there.  On
failure PR's status becomes `error', its error slot holds the
message, and CALLBACK still runs."
  (setf (gh-review-pr-status pr) 'loading
        (gh-review-pr-error pr) nil
        (gh-review-pr-all-paths pr) nil)
  (let ((on-error (lambda (message)
                    (setf (gh-review-pr-status pr) 'error
                          (gh-review-pr-error pr) message)
                    (funcall callback pr))))
    (gh-review--fetch-metadata
     pr
     (lambda ()
       (gh-review--fetch-merge-base
        pr
        (lambda ()
          (gh-review--fetch-commits
           pr
           (lambda ()
             (gh-review--fetch-diff
              pr
              (lambda ()
                (gh-review--read-blobs
                 pr
                 (lambda ()
                   (setf (gh-review-pr-status pr) 'ready)
                   (run-hook-with-args 'gh-review-after-fetch-hook pr)
                   (funcall callback pr))
                 on-error))
              on-error))
           on-error))
        on-error))
     on-error)))

;;; Writing to GitHub

(defvar gh-review-before-publish-functions nil
  "Functions called with the text of anything about to be posted.
Each receives the text and the pull request; one that signals an
error stops the post.")

(defun gh-review--check-publish (pr &rest texts)
  "Run `gh-review-before-publish-functions' over TEXTS for PR."
  (dolist (text texts)
    (when (and text (not (string-empty-p text)))
      (run-hook-with-args 'gh-review-before-publish-functions text pr))))

(defun gh-review--api-post (pr endpoint payload callback)
  "POST PAYLOAD, a JSON-serializable value, to the REST ENDPOINT.
CALLBACK receives the parsed response; errors are reported as
messages naming PR."
  (gh-review--gh-async
   (list "api" "--method" "POST" endpoint "--input" "-")
   callback
   :input (json-serialize payload)
   :error (lambda (message)
            (message "gh-review %s: %s" (gh-review-pr-key pr) message))))

(defun gh-review-submit-review (pr event body comments callback)
  "Submit a review of PR and call CALLBACK when GitHub accepted it.
EVENT is \"APPROVE\", \"REQUEST_CHANGES\" or \"COMMENT\"; BODY the
review text; COMMENTS a list of plists with :path :line :side and
:body, optionally :start-line and :start-side for a range."
  (apply #'gh-review--check-publish pr body
         (mapcar (lambda (c) (plist-get c :body)) comments))
  (gh-review--api-post
   pr (format "repos/%s/pulls/%d/reviews" (gh-review-pr-name-with-owner pr)
              (gh-review-pr-number pr))
   `(:commit_id ,(gh-review-pr-head-oid pr)
     :event ,event
     :body ,(or body "")
     :comments
     ,(vconcat
       (mapcar (lambda (c)
                 (append
                  (list :path (plist-get c :path)
                        :line (plist-get c :line)
                        :side (plist-get c :side)
                        :body (plist-get c :body))
                  (when (plist-get c :start-line)
                    (list :start_line (plist-get c :start-line)
                          :start_side (or (plist-get c :start-side)
                                          (plist-get c :side))))))
               comments)))
   callback))

(defun gh-review-post-comment (pr body callback)
  "Post BODY as a conversation comment on PR, then CALLBACK."
  (gh-review--check-publish pr body)
  (gh-review--api-post
   pr (format "repos/%s/issues/%d/comments" (gh-review-pr-name-with-owner pr)
              (gh-review-pr-number pr))
   `(:body ,body)
   callback))

(defun gh-review-reply-to-thread (pr comment-id body callback)
  "Reply BODY to the review thread holding COMMENT-ID on PR, then CALLBACK."
  (gh-review--check-publish pr body)
  (gh-review--api-post
   pr (format "repos/%s/pulls/%d/comments/%d/replies"
              (gh-review-pr-name-with-owner pr) (gh-review-pr-number pr)
              comment-id)
   `(:body ,body)
   callback))

(defun gh-review--graphql-mutation (mutation variables callback)
  "Run GraphQL MUTATION with VARIABLES, an alist of strings, then CALLBACK."
  (gh-review--gh-async
   (append (list "api" "graphql" "-f" (concat "query=" mutation))
           (mapcan (lambda (pair)
                     (list "-f" (format "%s=%s" (car pair) (cdr pair))))
                   variables))
   (lambda (_) (funcall callback))
   :error (lambda (message) (message "gh-review: %s" message))))

(defun gh-review-set-thread-resolved (thread-id resolved callback)
  "Resolve the review thread THREAD-ID, or unresolve it unless RESOLVED.
CALLBACK runs once GitHub accepted the change."
  (gh-review--graphql-mutation
   (format "mutation($id: ID!) { %s(input: {threadId: $id}) { clientMutationId } }"
           (if resolved "resolveReviewThread" "unresolveReviewThread"))
   `(("id" . ,thread-id))
   callback))

(defun gh-review-set-file-viewed (pr path viewed callback)
  "Mark PATH of PR as viewed on GitHub, or unviewed unless VIEWED.
CALLBACK runs once GitHub accepted the change."
  (gh-review--graphql-mutation
   (format "mutation($id: ID!, $path: String!) { %s(input: {pullRequestId: $id, path: $path}) { clientMutationId } }"
           (if viewed "markFileAsViewed" "unmarkFileAsViewed"))
   `(("id" . ,(gh-review-pr-id pr)) ("path" . ,path))
   (lambda ()
     (setf (alist-get path (gh-review-pr-viewed pr) nil nil #'equal) viewed)
     (funcall callback))))

(defun gh-review-merge (pr method callback)
  "Merge PR with METHOD, a symbol among `gh-review-pr-merge-methods'.
CALLBACK runs once GitHub merged it."
  (gh-review--gh-async
   (list "pr" "merge" (number-to-string (gh-review-pr-number pr))
         "--repo" (gh-review-pr-name-with-owner pr)
         (format "--%s" method)
         "--match-head-commit" (gh-review-pr-head-oid pr))
   (lambda (_) (funcall callback))
   :raw t
   :error (lambda (message) (message "gh-review: %s" message))))

;;; Drafts

(defun gh-review--drafts-file (pr)
  "File holding PR's unsent review comments."
  (expand-file-name (format "drafts/%s/%s/%d.eld" (gh-review-pr-owner pr)
                            (gh-review-pr-repo pr) (gh-review-pr-number pr))
                    gh-review-cache-directory))

(defun gh-review-load-drafts (pr)
  "Read PR's unsent review comments from disk into PR."
  (let ((file (gh-review--drafts-file pr)))
    (setf (gh-review-pr-drafts pr)
          (when (file-readable-p file)
            (with-temp-buffer
              (insert-file-contents file)
              (ignore-errors (read (current-buffer))))))))

(defun gh-review-save-drafts (pr)
  "Write PR's unsent review comments to disk."
  (let ((file (gh-review--drafts-file pr)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (let ((print-length nil) (print-level nil))
        (prin1 (gh-review-pr-drafts pr) (current-buffer))))))

(provide 'gh-review-core)
;;; gh-review-core.el ends here
