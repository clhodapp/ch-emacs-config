;; SPDX-License-Identifier: MIT
;; init consult-gh
(declare-function consult-gh-dashboard "consult-gh")
(declare-function consult-gh--get-split-style-character "consult-gh")
(declare-function consult-gh--dashboard-issues-assigned-builder "consult-gh")
(declare-function consult-gh--dashboard-issues-authored-builder "consult-gh")
(declare-function consult-gh--dashboard-issues-involves-builder "consult-gh")
(declare-function consult-gh--dashboard-issues-mentions-builder "consult-gh")
(declare-function consult-gh--search-dashboard-transform "consult-gh")
(declare-function consult--async-transform "consult")
(declare-function consult--process-collection "consult")
(defvar consult-gh--dashboard-assigned-to-user)
(defvar consult-gh--dashboard-authored-by-user)
(defvar consult-gh--dashboard-involves-user)
(defvar consult-gh--dashboard-mentions-user)
(defvar consult-gh-dashboard-items-sources)
(defvar consult-gh-args)
(defvar consult-gh-dashboard-maxnum)
(declare-function consult-gh--split-command "consult-gh")
;; The trio loads at startup rather than on first use: pr-review
;; resolves its API token through the delegation mode's ghub--token
;; override (`gh auth token`, backed by the system keyring), so the
;; override must be live before the first review command, whichever
;; surface it enters through. There is no auth-source entry for
;; github.com — the keyring-held gh credential is the only secret.
(use-package consult-gh-with-pr-review
  :demand t

  :config
  ;; Selecting a PR anywhere (search, dashboard, notifications,
  ;; embark) opens it in pr-review — the review surface. The native
  ;; viewer remains reachable only through consult-gh's own operate
  ;; commands, which stay unbound.
  (consult-gh-with-pr-review-mode 1))

(use-package consult-gh-embark
  :demand t

  :config
  (consult-gh-embark-mode 1))

;; Dashboard noise filters, applied in the search queries themselves.
;; Archived repositories freeze their open issues/PRs, so items from
;; them cannot be dismissed item-by-item; old and dormant items are
;; cut by rolling date windows, computed per query so they track the
;; current day. consult-gh has no extra-args knob for its dashboard
;; builders; the sources list is the documented extension point, so
;; rebuild each stock source around a wrapped builder.
(defvar ch/consult-gh-dashboard-max-age-days 182
  "Hide dashboard items created more than this many days ago.")

(defvar ch/consult-gh-dashboard-max-stale-days 14
  "Hide dashboard items whose last update is older than this many days.")

(defvar ch/consult-gh-dashboard-time-filters t
  "When non-nil, apply the rolling time windows to dashboard queries.
The archived-repository exclusion applies regardless.")

;; GitHub-side pacing: consult restarts the external query whenever the
;; async input changes, and GitHub's search API allows 30 requests per
;; minute. Let-bind consult's global knobs (defaults 0.2s/0.5s) tighter
;; around the consult-gh commands only, so local async consults (grep,
;; find) keep their stock responsiveness.
(defvar ch/consult-gh-input-debounce 0.6
  "Seconds of typing pause before a consult-gh query restarts.")

(defvar ch/consult-gh-input-throttle 1.5
  "Minimum seconds between consult-gh query restarts while typing.")

(defun ch/consult-gh--paced (command)
  "Call COMMAND interactively with GitHub-appropriate async pacing."
  (let ((consult-async-input-debounce ch/consult-gh-input-debounce)
        (consult-async-input-throttle ch/consult-gh-input-throttle))
    (call-interactively command)))

;; The default PR view is the attention set: PRs whose review is
;; requested from you, plus PRs in your repositories. gh search flags
;; AND together, so the union takes two sources; they ride the
;; dashboard machinery (consult--multi, delegation to pr-review,
;; grouping, preview) via a let-bound sources list. No time windows
;; here — a PR awaiting review must not silently expire; archived
;; repositories stay excluded.
(defvar ch/consult-gh--dashboard-sep (make-string 6 ?\u2006)
  "consult-gh's dashboard field separator: six six-per-em spaces.
Copied byte-exactly from its builders; the candidate formatter splits
on this.")

(defun ch/consult-gh--pr-search-builder (flags query reason input)
  "Dashboard-format `gh search prs' builder with FLAGS, tagged REASON.
QUERY is a list of fixed search-qualifier terms (e.g. \"-author:@me\"),
appended after a \"--\" flag terminator since qualifiers may begin
with a dash. INPUT is split per consult-gh convention into typed
query terms and extra args."
  (pcase-let* ((sep ch/consult-gh--dashboard-sep)
               (cmd (append consult-gh-args
                            (list "search" "prs" "--sort" "updated")
                            flags
                            (list "--archived=false"
                                  "--json" "isPullRequest,repository,title,number,labels,updatedAt,state,url,commentsCount"
                                  "--template"
                                  (concat "{{range .}}" "{{.isPullRequest}}" sep
                                          "{{.repository.nameWithOwner}}" sep
                                          "{{.title}}" sep "{{.number}}" sep
                                          "{{.state}}" sep "{{.updatedAt}}" sep
                                          "{{.labels}}" sep "{{.url}}" sep
                                          "{{.commentsCount}}" sep
                                          reason "\n" "{{end}}"))))
               (`(,arg . ,opts) (consult-gh--split-command input))
               (all (append cmd opts)))
    (unless (or (member "-s" all) (member "--state" all))
      (setq opts (append opts (list "--state" "open"))))
    (unless (or (member "-L" all) (member "--limit" all))
      (setq opts (append opts (list "--limit" (format "%s" consult-gh-dashboard-maxnum)))))
    (cons (append cmd opts (remove nil (list arg))
                  (and query (cons "--" query)))
          nil)))

(defun ch/consult-gh--pr-source (name narrow flags query reason)
  "Dashboard-style source NAME on NARROW key querying prs with FLAGS.
QUERY is a list of fixed search-qualifier terms. Inherits everything
but the query from the stock assigned source."
  (let ((s (copy-sequence consult-gh--dashboard-assigned-to-user)))
    (setq s (plist-put s :name name))
    (setq s (plist-put s :narrow narrow))
    (plist-put s :async
               (consult--process-collection
                (apply-partially #'ch/consult-gh--pr-search-builder flags query reason)
                :transform (consult--async-transform
                            #'consult-gh--search-dashboard-transform)
                :min-input 0))))

(defvar ch/consult-gh-watched-owners nil
  "Extra owners (users or orgs) whose repos join the maintainer queue.
Same-type search qualifiers OR together, so these merge into the
my-repos source as additional --owner flags. Example: (\"some-org\").")

(defvar ch/consult-gh-watched-repos nil
  "Specific owner/repo entries watched for others' PRs.
repo: and user: qualifiers AND across types, so these get their own
source rather than merging. Example: (\"minad/consult\").")

(defun ch/consult-gh--pr-attention-sources ()
  "Build the attention-set sources from the current rosters.
Called per invocation, so `setq' on the rosters applies immediately."
  (append
   (list (ch/consult-gh--pr-source
          "Review requested" ?r
          '("--review-requested" "@me") nil
          "Review requested from me")
         (ch/consult-gh--pr-source
          "Others' PRs on my repos" ?m
          (append '("--owner" "@me")
                  (mapcan (lambda (o) (list "--owner" o))
                          ch/consult-gh-watched-owners))
          '("-author:@me")
          "On my repositories, not authored by me"))
   (when ch/consult-gh-watched-repos
     (list (ch/consult-gh--pr-source
            "Watched repos" ?w
            (mapcan (lambda (r) (list "--repo" r))
                    ch/consult-gh-watched-repos)
            '("-author:@me")
            "In watched repositories, not authored by me")))))

(defun ch/consult-gh-search-prs ()
  "PRs needing attention: review requested, maintainer queue, watched.
Fetches once (split seed) and filters locally; narrow with r / m / w.
`ch/consult-gh-search-prs-global' searches all of GitHub."
  (interactive)
  (let ((consult-gh-dashboard-items-sources (ch/consult-gh--pr-attention-sources))
        (c (consult-gh--get-split-style-character))
        (consult-async-input-debounce ch/consult-gh-input-debounce)
        (consult-async-input-throttle ch/consult-gh-input-throttle))
    (consult-gh-dashboard (concat c c) nil "Search PRs:  ")))

(defun ch/consult-gh-search-prs-global ()
  "`consult-gh-search-prs' across all of GitHub, with async pacing."
  (interactive)
  (ch/consult-gh--paced #'consult-gh-search-prs))

(defun ch/consult-gh-search-issues ()
  "`consult-gh-search-issues' with GitHub-appropriate async pacing."
  (interactive)
  (ch/consult-gh--paced #'consult-gh-search-issues))

(defun ch/consult-gh-notifications ()
  "`consult-gh-notifications' with GitHub-appropriate async pacing."
  (interactive)
  (ch/consult-gh--paced #'consult-gh-notifications))

(defun ch/consult-gh--dashboard-cutoff (days)
  "Date DAYS ago as a gh search after-this qualifier string."
  (concat ">" (format-time-string
               "%Y-%m-%d" (time-subtract nil (days-to-time days)))))

(defun ch/consult-gh--dashboard-filter-builder (builder input)
  "Run dashboard BUILDER on INPUT with the noise filters appended."
  (pcase-let ((`(,cmd . ,highlight) (funcall builder input)))
    (cons (append cmd
                  (list "--archived=false")
                  (when ch/consult-gh-dashboard-time-filters
                    (list "--created" (ch/consult-gh--dashboard-cutoff
                                       ch/consult-gh-dashboard-max-age-days)
                          "--updated" (ch/consult-gh--dashboard-cutoff
                                       ch/consult-gh-dashboard-max-stale-days))))
          highlight)))

(defun ch/consult-gh-dashboard ()
  "`consult-gh-dashboard', fetching once and filtering locally.
Seeds the minibuffer with an empty async section (two split
characters), so each source's search query runs once per invocation
and typing narrows the results locally. GitHub's search API allows
only 30 requests per minute; the stock behavior re-queries all four
sources whenever the async input changes. Delete the seed characters
to get server-side terms and the -- extra-args syntax back."
  (interactive)
  (let ((c (consult-gh--get-split-style-character))
        (consult-async-input-debounce ch/consult-gh-input-debounce)
        (consult-async-input-throttle ch/consult-gh-input-throttle))
    (consult-gh-dashboard (concat c c))))

(defun ch/consult-gh-dashboard-all ()
  "`ch/consult-gh-dashboard' without the rolling time windows.
Still excludes archived repositories. The let-binding holds through
the minibuffer session, so the async builders see it."
  (interactive)
  (let ((ch/consult-gh-dashboard-time-filters nil))
    (ch/consult-gh-dashboard)))

(defun ch/consult-gh--dashboard-source (source builder)
  "Copy dashboard SOURCE, rebuilding :async around wrapped BUILDER."
  (plist-put (copy-sequence source) :async
             (consult--process-collection
              (apply-partially #'ch/consult-gh--dashboard-filter-builder builder)
              :transform (consult--async-transform
                          #'consult-gh--search-dashboard-transform)
              :min-input 0)))

(with-eval-after-load 'consult-gh
  (setq consult-gh-dashboard-items-sources
        (list (ch/consult-gh--dashboard-source
               consult-gh--dashboard-assigned-to-user
               #'consult-gh--dashboard-issues-assigned-builder)
              (ch/consult-gh--dashboard-source
               consult-gh--dashboard-mentions-user
               #'consult-gh--dashboard-issues-mentions-builder)
              (ch/consult-gh--dashboard-source
               consult-gh--dashboard-involves-user
               #'consult-gh--dashboard-issues-involves-builder)
              (ch/consult-gh--dashboard-source
               consult-gh--dashboard-authored-by-user
               #'consult-gh--dashboard-issues-authored-builder))))

(with-eval-after-load 'evil
  (ch/leader-prefix-title "g" "git")
  ;; g d is magit-diff-unstaged; h = "hub". Capital H = the same view
  ;; without the time windows (claude-queue's uppercase --all idiom).
  (evil-global-set-key 'motion (kbd "<leader> g h") #'ch/consult-gh-dashboard)
  (evil-global-set-key 'motion (kbd "<leader> g H") #'ch/consult-gh-dashboard-all)
  (evil-global-set-key 'motion (kbd "<leader> g i") #'ch/consult-gh-search-issues)
  (evil-global-set-key 'motion (kbd "<leader> g n") #'ch/consult-gh-notifications)
  (evil-global-set-key 'motion (kbd "<leader> g p") #'ch/consult-gh-search-prs)
  ;; Capital = the unscoped view, per the uppercase idiom.
  (evil-global-set-key 'motion (kbd "<leader> g P") #'ch/consult-gh-search-prs-global))
