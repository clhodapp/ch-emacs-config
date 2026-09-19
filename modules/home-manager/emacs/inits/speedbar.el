;; SPDX-License-Identifier: MIT
;; init speedbar (Emacs 31 same-frame speedbar: three toggleable trees)
(eval-when-compile
  (require 'speedbar)
  (require 'project))
(declare-function dframe-click "dframe")
(declare-function evil-define-key* "evil-core")
(declare-function imenu--make-index-alist "imenu")
(declare-function imenu--subalist-p "imenu")
(declare-function magit-current-section "magit-section")
(declare-function magit-file-section-p "magit-section")
(declare-function nerd-icons-faicon "nerd-icons")
(declare-function project-current "project")
(declare-function project-root "project")
(declare-function slot-value "eieio-core")
(declare-function speedbar-add-expansion-list "speedbar")
(declare-function speedbar-change-expand-button-char "speedbar")
(declare-function speedbar-change-initial-expansion-list "speedbar")
(declare-function speedbar-delete-subblock "speedbar")
(declare-function speedbar-file-lists "speedbar")
(declare-function speedbar-frame-or-window "speedbar")
(declare-function speedbar-make-specialized-keymap "speedbar")
(declare-function speedbar-make-tag-line "speedbar")
(declare-function speedbar-mode "speedbar")
(declare-function speedbar-refresh "speedbar")
(declare-function speedbar-reset-scanners "speedbar")
(declare-function speedbar-timer-fn "speedbar")
(declare-function speedbar-toggle-line-expansion "speedbar")
(declare-function nerd-icons-octicon "nerd-icons")
(declare-function pr-review--find-all-file-names "pr-review-action")
(declare-function pr-review-goto-file "pr-review-action")
(defvar imenu--index-alist)
(defvar pr-review--pr-path)
(defvar pr-review-mode-map)

(use-package speedbar
  :commands
  (speedbar-window-mode)

  :custom
  (speedbar-prefer-window t "M-x speedbar opens the side window, not a frame")
  (speedbar-use-images nil "text {+}/{-} expanders instead of legacy icons")
  (speedbar-show-unknown-files t
                               "the default extension whitelist predates most
of this config's languages; .nix files would be invisible")

  :config
  ;; Speedbar is a mouse-2 interface: dframe binds mouse-2 to
  ;; `dframe-click' and leaves mouse-1 to Emacs's link-following, via a
  ;; [follow-link] binding of `mouse-face' that makes every button count
  ;; as a link.  Under evil that misfires.  evil-collection puts speedbar
  ;; buffers in normal state without `evil-make-overriding-map', so evil's
  ;; state keymap outranks `speedbar-mode-map' and mouse-2 resolves to
  ;; `mouse-yank-primary'; evil's own `down-mouse-1' handler then rewrites
  ;; a press on a button into that mouse-2 and yanks into the tree.
  ;; Binding mouse-1 where evil will find it, and dropping the
  ;; [follow-link] entry so no rewrite happens, is the same treatment
  ;; evil-collection gives its own list-view mode.  `dframe-click' acts on
  ;; the button under point, so an expander toggles and a name visits,
  ;; matching RET.  The [follow-link] entry lives in `speedbar-mode-map'
  ;; itself, so clearing it needs `define-key' there; `evil-define-key'
  ;; writes to an auxiliary map and would leave the original in place.
  ;; The repeat variants matter as much as the single press: toggling a
  ;; directory open and shut again lands two presses inside
  ;; `double-click-time', and Emacs delivers the second as
  ;; `double-mouse-1'.  Unbound, it does nothing and the toggle appears
  ;; to swallow every other press.  Emacs caps its synthesized repeat
  ;; modifiers at triple (keyboard.c raises the triple modifier for any
  ;; count above two), so these two cover four presses and beyond.
  (define-key speedbar-mode-map [follow-link] nil)
  (evil-define-key 'normal speedbar-mode-map
    [mouse-1] #'dframe-click
    [double-mouse-1] #'dframe-click
    [triple-mouse-1] #'dframe-click)

  (ch/speedbar--hide-stock-displays)

  ;; The outline tree re-targets when the selected buffer changes;
  ;; both hooks feed the same cheap guard.
  (add-hook 'window-buffer-change-functions #'ch/speedbar--outline-follow)
  (add-hook 'window-selection-change-functions #'ch/speedbar--outline-follow))

(defvar ch/speedbar--flavor nil
  "Tree the speedbar side window shows: `outline', `project' or `pr'.")

(defvar ch/speedbar--outline-buffer nil
  "Source buffer the Outline display renders.")

(defvar ch/speedbar--outline-followed nil
  "Source position of the identifier the outline's point last followed to.
Nil when no identifier has been followed to, which is also what a
re-target to another buffer resets it to.")

(defvar ch/speedbar--outline-preview-window nil
  "Window the outline preview displays in, chosen on entering the tree.")

(defvar ch/speedbar--outline-preview-restore nil
  "State to put the preview window back to, as (BUFFER POINT START).
Nil when there is nothing to restore, which is the state RET leaves
behind after committing a jump.")

(defvar ch/speedbar--outline-previewed nil
  "Source position the preview last showed, so repeats cost nothing.")

(defun ch/speedbar--toggle (flavor fill)
  "Toggle the speedbar side window as tree FLAVOR.
A second toggle of the same flavor closes the window; a different
flavor takes the window over.  FILL is called with the invoking
buffer current to render the content once the window is up.  Every
flavor pins its rendered tree (speedbar's idle-timer updates stay
off); the trees re-target through their own hooks instead."
  (require 'speedbar)
  (if (and (eq (speedbar-frame-or-window) 'window)
           (eq ch/speedbar--flavor flavor))
      (progn
        (speedbar-window-mode -1)
        (setq ch/speedbar--flavor nil))
    (setq speedbar-update-flag nil)
    (speedbar-window-mode 1)
    ;; Emacs 31.1's `speedbar-window-mode' never puts its buffer into
    ;; `speedbar-mode', though its docstring says it does; only the older
    ;; `speedbar-frame-mode' calls it.  Without the major mode the buffer
    ;; has no speedbar keymap at all, so RET and the mouse fall through to
    ;; evil's normal-state bindings.  There, pressing mouse-1 on a button
    ;; (buttons carry mouse-face, so evil rewrites the event to mouse-2 as
    ;; a link-follow) runs `mouse-yank-primary' and pastes into the tree.
    ;; Guarded so it becomes a no-op if a later Emacs sets the mode itself:
    ;; re-entering the mode runs `kill-all-local-variables', which would
    ;; discard `speedbar-initial-expansion-list-name' and with it the
    ;; chosen display.
    (with-current-buffer speedbar-buffer
      (unless (derived-mode-p 'speedbar-mode)
        (speedbar-mode)))
    ;; The side window carries no-other-window, which evil's window
    ;; motions (windmove) respect; without this the tree would be
    ;; reachable only by mouse.  The window stays dedicated.
    (set-window-parameter (get-buffer-window speedbar-buffer)
                          'no-other-window nil)
    (funcall fill)
    (setq ch/speedbar--flavor flavor)))

(defun ch/speedbar--show-display (name dir)
  "Show expansion-list display NAME rooted at DIR in the speedbar buffer.
The initial render inside `speedbar-window-mode' uses whatever
display and directory a reused speedbar buffer had, and the idle
timer never re-roots for non-file buffers (nor at all when updates
are off), so both are set explicitly.
`speedbar-change-initial-expansion-list' refreshes by itself while
the speedbar is up."
  (with-current-buffer speedbar-buffer
    (setq default-directory dir)
    ;; The text cache would restore the previous display's rendering
    ;; when returning to a cached directory; flavors switch displays,
    ;; so a stale restore would show the wrong tree.
    (setq speedbar-full-text-cache nil)
    (speedbar-change-initial-expansion-list name)))

(defun ch/speedbar-outline-tree ()
  "Toggle a speedbar tree of the identifiers in the current buffer.
The buffer's imenu structure (tree-sitter-backed in the ts modes)
rendered as a collapsible tree.  The tree's point tracks the
identifier point is inside of; moving it in the tree previews that
identifier in the window the tree was entered from, and RET commits
the jump.  The outline re-targets as the selected buffer changes;
gr refreshes it after edits."
  (interactive)
  (let ((buffer (current-buffer)))
    (ch/speedbar--toggle 'outline
                         (lambda ()
                           (ch/speedbar--outline-register)
                           (setq ch/speedbar--outline-buffer buffer)
                           (setq ch/speedbar--outline-followed nil)
                           (setq ch/speedbar--outline-previewed nil)
                           (setq ch/speedbar--outline-preview-restore nil)
                           (ch/speedbar--show-display "Outline"
                                                      default-directory)))))

(defun ch/speedbar-project-tree ()
  "Toggle a speedbar tree pinned at the current project's root.
The tree stays on the project while buffers change; expand
directories in place to walk the project."
  (interactive)
  (let ((root (project-root (project-current t))))
    (ch/speedbar--toggle 'project
                         (lambda ()
                           (ch/speedbar--project-register)
                           (with-current-buffer speedbar-buffer
                             (ch/speedbar--project-arm-context-menu))
                           (ch/speedbar--show-display "Project" root)))))

(defvar-local ch/speedbar--pr-followed-file nil
  "File the PR tree's point last followed to (pr-review buffer local).")

(defun ch/speedbar-pr-tree ()
  "Toggle a speedbar tree of the current PR's changed files.
Bound in pr-review buffers; the tree is pinned to the PR it was
opened from, so visiting files does not replace it."
  (interactive)
  (ch/speedbar--toggle 'pr
                       (lambda ()
                         (setq ch/speedbar--pr-followed-file nil)
                         ;; A forced timer pass dispatches to
                         ;; `pr-review-speedbar-buttons' for the
                         ;; selected pr-review buffer.
                         (let ((speedbar-update-flag t))
                           (speedbar-timer-fn)))))

;; --- Project display -------------------------------------------------
;; A top-level speedbar display registered through
;; `speedbar-add-expansion-list', the documented extension point for
;; new displays.  Unlike the stock "files" display it renders every
;; line with a nerd-icons glyph; unlike the PR tree it reads directory
;; contents lazily at expansion time, so large projects cost only what
;; is opened.  File tag expansion stays with the "files" display.

(defvar ch/speedbar--project-menu nil
  "Extra Displays-menu items for the Project display (none).")

(defvar ch/speedbar--project-key-map nil
  "Specialized keymap for the Project display, built on first use.")

(defun ch/speedbar--project-register ()
  "Register the Project display; speedbar must already be loaded."
  (unless ch/speedbar--project-key-map
    (setq ch/speedbar--project-key-map (speedbar-make-specialized-keymap))
    ;; A specialized keymap is the display's local map, which evil's
    ;; state keymaps outrank, so a plain `define-key' of \"D\" here would
    ;; lose to evil's delete-to-end-of-line.  `evil-define-key' writes
    ;; into the auxiliary map evil consults for this keymap instead.
    (evil-define-key 'normal ch/speedbar--project-key-map
      "D" #'ch/speedbar--project-delete)
    (speedbar-add-expansion-list
     '("Project" ch/speedbar--project-menu ch/speedbar--project-key-map
       ch/speedbar--project-buttons))))

(defun ch/speedbar--project-buttons (dir _index)
  "Insert the project tree rooted at DIR (Project display entry point)."
  (require 'nerd-icons)
  (insert (ch/speedbar--dir-glyph t)
          " "
          (propertize (abbreviate-file-name (directory-file-name dir))
                      'face 'speedbar-directory-face)
          "\n")
  (ch/speedbar--project-insert-contents (expand-file-name dir) 0))

(defun ch/speedbar--project-insert-contents (dir depth)
  "Insert DIR's entries at DEPTH: subdirectories first, then files.
`speedbar-file-lists' applies speedbar's ignore rules (VC exclusions,
unshown regexps) and its directory cache."
  (let ((lists (speedbar-file-lists dir)))
    (dolist (sub (car lists))
      (speedbar-make-tag-line 'curly ?+ #'ch/speedbar--project-expand
                              (expand-file-name sub dir)
                              sub #'ch/speedbar--line-toggle nil
                              'speedbar-directory-face depth)
      (ch/speedbar--glyph-line (ch/speedbar--dir-glyph nil) t))
    (dolist (file (cadr lists))
      (speedbar-make-tag-line nil nil nil nil
                              file #'ch/speedbar--project-visit
                              (expand-file-name file dir)
                              'speedbar-file-face depth)
      (ch/speedbar--glyph-line (nerd-icons-icon-for-file file) t))))

(defun ch/speedbar--project-expand (text token indent)
  "Expand or contract a Project-tree directory (speedbar button contract).
TEXT is the activated button's text ({+} or {-}), TOKEN the
directory's absolute path, INDENT the line's depth.  Flipping the
button char drops its display glyph, so the folder glyph is re-applied
after each flip."
  (cond
   ((string-search "+" text)
    (speedbar-change-expand-button-char ?-)
    (ch/speedbar--glyph-line (ch/speedbar--dir-glyph t))
    (speedbar-with-writable
      (save-excursion
        (end-of-line)
        (forward-char 1)
        (ch/speedbar--project-insert-contents token (1+ indent)))))
   ((string-search "-" text)
    (speedbar-change-expand-button-char ?+)
    (ch/speedbar--glyph-line (ch/speedbar--dir-glyph nil))
    (speedbar-delete-subblock indent))))

(defun ch/speedbar--line-toggle (_text _token _indent)
  "Expand or contract the tree line at point (RET on the name).
Shared by Project directories and Outline groups."
  (speedbar-toggle-line-expansion))

(defun ch/speedbar--project-visit (_text path _indent)
  "Visit PATH in a normal window, leaving the tree in place."
  (pop-to-buffer (find-file-noselect path)))

(defun ch/speedbar--project-token-at (&optional position)
  "Speedbar token on the line at POSITION, or nil.
POSITION defaults to point.  `speedbar-line-token' cannot be used
here: it looks for the token at the line's name text, whereas a
Project-tree directory carries its path on the expander button, and
its regexp expects a bracketed button, which a file line's bare \">\"
marker is not.  Scanning the line finds the token either place, the
same way `ch/speedbar--outline-token-at-point' does."
  (save-excursion
    (when position (goto-char position))
    (let ((end (line-end-position))
          (token nil))
      (beginning-of-line)
      (while (and (not token) (< (point) end))
        (setq token (get-text-property (point) 'speedbar-token))
        (goto-char (next-single-property-change
                    (point) 'speedbar-token nil end)))
      token)))

(defun ch/speedbar--project-entry-at (&optional position)
  "The Project-tree entry on the line at POSITION, or nil.
Return (PATH . DIRECTORY-P).  POSITION defaults to point, and is
where a mouse click landed when the context menu asks, since a
right-click does not move point.  Both line kinds carry the absolute
path as their token; the root line carries none and yields nil, so
the tree cannot delete the project it is rooted at."
  (let ((token (ch/speedbar--project-token-at position)))
    (when (stringp token)
      (cons token (file-directory-p token)))))

(defun ch/speedbar--project-line-depth ()
  "Depth of the tree line at point, as `speedbar-delete-subblock' means it.
Speedbar writes the depth into each line as its \"NN:\" prefix."
  (save-excursion
    (beginning-of-line)
    (when (looking-at "^\\([0-9]+\\):")
      (string-to-number (match-string 1)))))

(defun ch/speedbar--project-drop-line ()
  "Remove the tree line at point, along with any subtree beneath it.
Editing the tree in place keeps the expansion state of every other
directory, which a full `speedbar-refresh' would throw away."
  (when-let* ((depth (ch/speedbar--project-line-depth)))
    (speedbar-delete-subblock depth))
  (speedbar-with-writable
    (delete-region (line-beginning-position)
                   (min (point-max) (1+ (line-end-position))))))

(defun ch/speedbar--project-delete (&optional position)
  "Delete the file or directory on the Project-tree line at POSITION.
POSITION defaults to point.  Confirmation is required: the prompt
names the full path and, for a directory, says that the delete is
recursive.  Buffers visiting what was deleted are killed, since they
would otherwise offer to write the file back.  Deletion honors
`delete-by-moving-to-trash', which `delete-file' and
`delete-directory' consult when passed TRASH.

Point ends on the line that took the deleted one's place, so a
`save-excursion' around the whole command would restore a position
inside text that is no longer there."
  (interactive)
  (when position (goto-char position))
  (let* ((entry (or (ch/speedbar--project-entry-at)
                    (user-error "No file or directory on this line")))
         (path (car entry))
         (directory-p (cdr entry)))
    (cond
     ((not (file-exists-p path))
      (ch/speedbar--project-drop-line)
      (message "%s was already gone" (abbreviate-file-name path)))
     ((yes-or-no-p (format "Delete %s %s? "
                           (if directory-p "directory and its contents"
                             "file")
                           (abbreviate-file-name path)))
      (if directory-p
          (delete-directory path t t)
        (delete-file path t))
      (dolist (buffer (buffer-list))
        (when-let* ((file (buffer-file-name buffer)))
          (when (or (equal file path)
                    (and directory-p
                         (string-prefix-p (file-name-as-directory path)
                                          file)))
            (kill-buffer buffer))))
      ;; `speedbar-file-lists' caches directory contents, and would
      ;; hand the deleted name back the next time its parent expands.
      (speedbar-reset-scanners)
      (ch/speedbar--project-drop-line)
      (message "Deleted %s" (abbreviate-file-name path))))))

(defun ch/speedbar--project-line-of (path)
  "Position of PATH's line in the Project tree, or nil if it has none.
Both line kinds carry the absolute path as their speedbar token, so
one scan finds either."
  (save-excursion
    (goto-char (point-min))
    (let ((found nil))
      (while (and (not found) (not (eobp)))
        (if (equal (ch/speedbar--project-token-at) path)
            (setq found (line-beginning-position))
          (forward-line 1)))
      found)))

(defun ch/speedbar--project-context-menu (menu click)
  "Add the Project tree's entries to MENU for the right-click CLICK.
On `context-menu-functions', which every buffer's right-click
consults, so the entries are gated on being in a Project tree: other
speedbar flavors and every other buffer see the menu unchanged.  The
entries act on the line CLICK landed on rather than on point, which a
right-click leaves where it was.  The command closes over the path
rather than over the click position, and looks the path's line up
again when it runs, so a tree edited between the press and the menu
selection cannot delete a different file than the menu named."
  (when (and (derived-mode-p 'speedbar-mode)
             (eq ch/speedbar--flavor 'project))
    (when-let* ((position (posn-point (event-start click)))
                (entry (ch/speedbar--project-entry-at position))
                (path (car entry)))
      (define-key-after menu [ch/speedbar-project-separator]
        menu-bar-separator)
      (define-key-after menu [ch/speedbar-project-delete]
        `(menu-item ,(format "Delete %s"
                             (file-name-nondirectory
                              (directory-file-name path)))
                    ,(lambda ()
                       (interactive)
                       (if-let* ((line (ch/speedbar--project-line-of path)))
                           (ch/speedbar--project-delete line)
                         (user-error "%s is no longer in the tree"
                                     (abbreviate-file-name path))))
                    :help "Delete this file or directory from disk"))))
  menu)

(defun ch/speedbar--project-arm-context-menu ()
  "Contribute the Project tree's right-click entries in this buffer."
  (add-hook 'context-menu-functions
            #'ch/speedbar--project-context-menu 90 t))

;; --- Outline display -------------------------------------------------
;; A second own top-level display: the identifiers of one source
;; buffer, from its imenu index (tree-sitter-backed in the ts modes).
;; Groups (Functions, Classes, ...) carry chevron glyphs and collapse
;; like directories; identifiers carry a dot glyph and jump to their
;; definition.

(defvar ch/speedbar--outline-menu nil
  "Extra Displays-menu items for the Outline display (none).")

(defvar ch/speedbar--outline-key-map nil
  "Specialized keymap for the Outline display, built on first use.")

(defun ch/speedbar--outline-register ()
  "Register the Outline display; speedbar must already be loaded."
  (unless ch/speedbar--outline-key-map
    (setq ch/speedbar--outline-key-map (speedbar-make-specialized-keymap))
    (speedbar-add-expansion-list
     '("Outline" ch/speedbar--outline-menu ch/speedbar--outline-key-map
       ch/speedbar--outline-buttons))))

(defun ch/speedbar--group-glyph (open)
  "The outline-group glyph: a chevron, down when OPEN, else right."
  (nerd-icons-octicon (if open "nf-oct-chevron_down" "nf-oct-chevron_right")))

(defun ch/speedbar--outline-index (buffer)
  "BUFFER's imenu index, freshly scanned, without the *Rescan* entry.
The cache is dropped first so a gr refresh or buffer re-target sees
current identifiers, not the index from the last imenu use."
  (with-current-buffer buffer
    (require 'imenu)
    (setq imenu--index-alist nil)
    (seq-remove (lambda (item) (equal (car-safe item) "*Rescan*"))
                (condition-case nil
                    (imenu--make-index-alist t)
                  (error nil)))))

(defun ch/speedbar--outline-buttons (_dir _index)
  "Insert the identifier tree of the outline's source buffer."
  (require 'nerd-icons)
  (let ((buffer ch/speedbar--outline-buffer))
    (if (not (buffer-live-p buffer))
        (insert "No source buffer\n")
      (insert (nerd-icons-icon-for-file (buffer-name buffer))
              " "
              (propertize (buffer-name buffer)
                          'face 'speedbar-directory-face)
              "\n")
      (let ((index (ch/speedbar--outline-index buffer)))
        (if (null index)
            (insert " (no identifiers)\n")
          (ch/speedbar--outline-insert-items index buffer 0))))))

(defun ch/speedbar--outline-insert-items (items buffer depth)
  "Insert tag lines for imenu ITEMS of BUFFER at DEPTH.
Group items recurse; plain (NAME . POSITION) and special
\(NAME POSITION FUNCTION ...) entries become jump lines; anything
else is skipped."
  (dolist (item items)
    (let ((name (car-safe item)))
      (cond
       ((not (stringp name)))
       ((imenu--subalist-p item)
        (speedbar-make-tag-line 'curly ?- #'ch/speedbar--outline-expand
                                (list (cdr item) buffer)
                                name #'ch/speedbar--line-toggle nil
                                'speedbar-tag-face depth)
        (ch/speedbar--glyph-line (ch/speedbar--group-glyph t) t)
        (ch/speedbar--outline-insert-items (cdr item) buffer (1+ depth)))
       ((or (number-or-marker-p (cdr item))
            (number-or-marker-p (car-safe (cdr item))))
        (speedbar-make-tag-line nil nil nil nil
                                name #'ch/speedbar--outline-jump
                                (cons (if (number-or-marker-p (cdr item))
                                          (cdr item)
                                        (car (cdr item)))
                                      buffer)
                                'speedbar-tag-face depth)
        (ch/speedbar--glyph-line (nerd-icons-octicon "nf-oct-dot_fill") t))))))

(defun ch/speedbar--outline-expand (text token indent)
  "Expand or contract an outline group (speedbar button contract).
TEXT is the activated button's text ({+} or {-}), TOKEN is
(ITEMS BUFFER), INDENT the line's depth."
  (cond
   ((string-search "+" text)
    (speedbar-change-expand-button-char ?-)
    (ch/speedbar--glyph-line (ch/speedbar--group-glyph t))
    (speedbar-with-writable
      (save-excursion
        (end-of-line)
        (forward-char 1)
        (ch/speedbar--outline-insert-items (nth 0 token) (nth 1 token)
                                           (1+ indent)))))
   ((string-search "-" text)
    (speedbar-change-expand-button-char ?+)
    (ch/speedbar--glyph-line (ch/speedbar--group-glyph nil))
    (speedbar-delete-subblock indent))))

(defun ch/speedbar--outline-jump (_text token _indent)
  "Jump to TOKEN's (POSITION . BUFFER) identifier definition.
The preview the tree has been showing becomes the real position:
the saved state is dropped so leaving the tree does not undo it."
  (let ((position (car token))
        (buffer (cdr token)))
    (if (not (buffer-live-p buffer))
        (message "The outline's buffer is gone")
      (setq ch/speedbar--outline-preview-restore nil)
      (setq ch/speedbar--outline-previewed nil)
      (pop-to-buffer buffer)
      (goto-char position)
      (recenter))))

(defun ch/speedbar--outline-follow (&rest _)
  "Re-target the outline tree to the selected window's buffer.
On the window buffer/selection change hooks; a no-op unless the
outline is showing and a different file-visiting buffer is selected."
  (when (and (eq ch/speedbar--flavor 'outline)
             (eq (speedbar-frame-or-window) 'window))
    (let ((buffer (window-buffer (selected-window))))
      (when (and (buffer-live-p buffer)
                 (buffer-file-name buffer)
                 (not (eq buffer ch/speedbar--outline-buffer)))
        (setq ch/speedbar--outline-buffer buffer)
        (setq ch/speedbar--outline-followed nil)
        (with-current-buffer speedbar-buffer
          (speedbar-refresh))))))

(defun ch/speedbar--outline-enclosing-line (source-position)
  "Tree position of the identifier line enclosing SOURCE-POSITION.
Returns a (TREE-POSITION . IDENTIFIER-POSITION) pair, or nil when
no identifier line qualifies.  Runs in the speedbar buffer.
Identifier lines carry (POSITION . BUFFER) as their speedbar token
and group lines carry a list, so only identifiers match.  The lines
are in buffer order, so the last one starting at or before
SOURCE-POSITION is the innermost identifier containing it; a
collapsed group contributes no lines, so the nearest visible
ancestor is chosen instead."
  (save-excursion
    (goto-char (point-min))
    (let ((best nil)
          (match nil))
      (while (setq match (text-property-search-forward 'speedbar-token))
        (let ((token (prop-match-value match)))
          (when (and (consp token)
                     (number-or-marker-p (car token))
                     (bufferp (cdr token))
                     (<= (car token) source-position))
            (setq best (cons (prop-match-beginning match) (car token))))))
      best)))

(defun ch/speedbar--outline-point-follow ()
  "Move the outline tree's point to the identifier enclosing point.
On the global `post-command-hook'; a no-op unless the outline tree
is showing the current buffer, and while point has not left the
identifier the tree already sits on."
  (when (and (featurep 'speedbar)
             (eq ch/speedbar--flavor 'outline)
             (eq (speedbar-frame-or-window) 'window)
             (eq (current-buffer) ch/speedbar--outline-buffer))
    (let ((source-position (point)))
      (when-let* ((window (get-buffer-window speedbar-buffer))
                  (found (with-current-buffer speedbar-buffer
                           (ch/speedbar--outline-enclosing-line
                            source-position))))
        (unless (equal (cdr found) ch/speedbar--outline-followed)
          (setq ch/speedbar--outline-followed (cdr found))
          (set-window-point window (car found)))))))

;; --- Outline preview -------------------------------------------------
;; Moving point in the tree shows the identifier under it in the
;; window the tree was entered from, the way `consult-buffer' shows a
;; candidate while the minibuffer is up: the view moves, nothing is
;; committed, and leaving the tree without pressing RET puts the window
;; back where it was.  RET commits, through
;; `ch/speedbar--outline-jump'.

(defun ch/speedbar--outline-preview-save ()
  "Record the preview window and the view to restore on leaving.
Called when point enters the tree with no preview in progress.  The
window showing the tree's source buffer is preferred; when the
source buffer is not on screen the least recently used window other
than the tree takes the preview."
  (when-let* ((window (or (and (buffer-live-p ch/speedbar--outline-buffer)
                               (get-buffer-window
                                ch/speedbar--outline-buffer))
                          (get-lru-window nil nil t))))
    (unless (eq window (get-buffer-window speedbar-buffer))
      (setq ch/speedbar--outline-preview-window window)
      (setq ch/speedbar--outline-preview-restore
            (list (window-buffer window)
                  (window-point window)
                  (window-start window))))))

(defun ch/speedbar--outline-preview-undo ()
  "Put the preview window back to the view saved on entering the tree."
  (when-let* ((restore ch/speedbar--outline-preview-restore)
              (window ch/speedbar--outline-preview-window))
    (setq ch/speedbar--outline-preview-restore nil)
    (setq ch/speedbar--outline-previewed nil)
    (when (and (window-live-p window)
               (buffer-live-p (nth 0 restore)))
      (set-window-buffer window (nth 0 restore))
      (set-window-point window (nth 1 restore))
      (set-window-start window (nth 2 restore)))))

(defun ch/speedbar--outline-preview-show (position)
  "Show the source buffer at POSITION in the preview window.
Only the window's view moves; the buffer's own point is left alone,
so an abandoned preview costs the source buffer nothing."
  (when-let* ((window ch/speedbar--outline-preview-window)
              (buffer ch/speedbar--outline-buffer))
    (when (and (window-live-p window) (buffer-live-p buffer))
      (unless (eq (window-buffer window) buffer)
        (set-window-buffer window buffer))
      (set-window-point window position)
      (with-selected-window window
        (recenter)))))

(defun ch/speedbar--outline-token-at-point ()
  "Source position of the identifier line at point in the tree, or nil.
`speedbar-make-tag-line' hangs the token on the tag text rather
than the whole line, so the line is scanned for it.  Group lines
carry a list as their token and yield nil, leaving the preview on
whatever it already showed."
  (let ((end (line-end-position))
        (token nil))
    (save-excursion
      (beginning-of-line)
      (while (and (not token) (< (point) end))
        (setq token (get-text-property (point) 'speedbar-token))
        (goto-char (next-single-property-change
                    (point) 'speedbar-token nil end))))
    (when (and (consp token)
               (number-or-marker-p (car token))
               (bufferp (cdr token)))
      (car token))))

(defun ch/speedbar--outline-preview ()
  "Preview the tree line at point, or restore on leaving the tree.
On the global `post-command-hook'.  While point is in the outline
tree the identifier under it is shown in the window the tree was
entered from; when point leaves the tree with no RET having
committed, that window goes back to the view it had."
  (when (and (featurep 'speedbar) (eq ch/speedbar--flavor 'outline))
    (if (not (and (eq (speedbar-frame-or-window) 'window)
                  (eq (current-buffer) speedbar-buffer)))
        (ch/speedbar--outline-preview-undo)
      (unless ch/speedbar--outline-preview-restore
        (ch/speedbar--outline-preview-save))
      (let ((position (ch/speedbar--outline-token-at-point)))
        (when (and position
                   (not (equal position ch/speedbar--outline-previewed)))
          (setq ch/speedbar--outline-previewed position)
          (ch/speedbar--outline-preview-show position))))))

(add-hook 'post-command-hook #'ch/speedbar--outline-point-follow)
(add-hook 'post-command-hook #'ch/speedbar--outline-preview)

;; --- Buffers display -------------------------------------------------
;; A third own top-level display, replacing the stock "buffers" and
;; "quick buffers" entries: the live buffers in two groups, those
;; visiting a file and the rest.  Each line carries a nerd-icons glyph
;; and switches to its buffer, matching how the Project tree visits a
;; file.  Groups collapse like Project directories, so TAB and the evil
;; z-fold keys work on them.

(defvar ch/speedbar--buffers-menu nil
  "Extra Displays-menu items for the Buffers display (none).")

(defvar ch/speedbar--buffers-key-map nil
  "Specialized keymap for the Buffers display, built on first use.")

(defun ch/speedbar--buffers-register ()
  "Register the Buffers display; speedbar must already be loaded."
  (unless ch/speedbar--buffers-key-map
    (setq ch/speedbar--buffers-key-map (speedbar-make-specialized-keymap))
    (speedbar-add-expansion-list
     '("Buffers" ch/speedbar--buffers-menu ch/speedbar--buffers-key-map
       ch/speedbar--buffers-buttons))))

(defun ch/speedbar--buffers-list ()
  "Live buffers to show, as (FILE-VISITING . OTHER).
Buffers whose name starts with a space are internal and stay hidden,
as does the speedbar's own buffer."
  (let (files others)
    (dolist (buffer (buffer-list))
      (let ((name (buffer-name buffer)))
        (cond
         ((string-prefix-p " " name))
         ((eq buffer speedbar-buffer))
         ((buffer-file-name buffer) (push buffer files))
         (t (push buffer others)))))
    (cons (nreverse files) (nreverse others))))

(defun ch/speedbar--buffers-buttons (_dir _index)
  "Insert the buffer list (Buffers display entry point)."
  (require 'nerd-icons)
  (let* ((lists (ch/speedbar--buffers-list))
         (files (car lists))
         (others (cdr lists)))
    (insert (nerd-icons-octicon "nf-oct-stack")
            " "
            (propertize "Buffers" 'face 'speedbar-directory-face)
            "\n")
    (ch/speedbar--buffers-insert-group "Files" files 0)
    (ch/speedbar--buffers-insert-group "Other" others 0)))

(defun ch/speedbar--buffers-insert-group (name buffers depth)
  "Insert a collapsible group NAME at DEPTH holding BUFFERS.
Empty groups are skipped rather than shown as an empty heading."
  (when buffers
    (speedbar-make-tag-line 'curly ?- #'ch/speedbar--buffers-group-expand
                            buffers
                            name #'ch/speedbar--line-toggle nil
                            'speedbar-directory-face depth)
    (ch/speedbar--glyph-line (ch/speedbar--group-glyph t) t)
    (ch/speedbar--buffers-insert-items buffers (1+ depth))))

(defun ch/speedbar--buffers-insert-items (buffers depth)
  "Insert a tag line per buffer in BUFFERS at DEPTH."
  (dolist (buffer buffers)
    (let ((name (buffer-name buffer)))
      (speedbar-make-tag-line nil nil nil nil
                              name #'ch/speedbar--buffers-visit buffer
                              'speedbar-file-face depth)
      (ch/speedbar--glyph-line (nerd-icons-icon-for-file name) t))))

(defun ch/speedbar--buffers-group-expand (text token indent)
  "Expand or contract a Buffers group (speedbar button contract).
TEXT is the activated button's text ({+} or {-}), TOKEN the group's
buffer list, INDENT the line's depth.  Flipping the button char drops
its display glyph, so the chevron is re-applied after each flip."
  (cond
   ((string-search "+" text)
    (speedbar-change-expand-button-char ?-)
    (ch/speedbar--glyph-line (ch/speedbar--group-glyph t))
    (speedbar-with-writable
      (save-excursion
        (end-of-line) (forward-char 1)
        (ch/speedbar--buffers-insert-items token (1+ indent)))))
   ((string-search "-" text)
    (speedbar-change-expand-button-char ?+)
    (ch/speedbar--glyph-line (ch/speedbar--group-glyph nil))
    (speedbar-delete-subblock indent))))

(defun ch/speedbar--buffers-visit (_text buffer _indent)
  "Switch to BUFFER in a normal window, leaving the tree in place.
A buffer killed since the tree was drawn refreshes the list instead of
erroring."
  (if (buffer-live-p buffer)
      (pop-to-buffer buffer)
    (with-current-buffer speedbar-buffer
      (speedbar-refresh))))

(defun ch/speedbar-buffers-tree ()
  "Toggle a speedbar tree of the live buffers.
Buffers visiting a file are grouped separately from the rest; RET or
the left mouse button switches to the buffer on the line."
  (interactive)
  (ch/speedbar--toggle 'buffers
                       (lambda ()
                         (ch/speedbar--buffers-register)
                         (ch/speedbar--show-display "Buffers"
                                                    default-directory))))

(defun ch/speedbar--hide-stock-displays ()
  "Drop speedbar's own displays from the Displays menu.
The stock \"files\", \"buffers\" and \"quick buffers\" entries render
without glyphs and do not follow this configuration's tree
conventions; the Project, Outline and Buffers displays replace them.
`speedbar-initial-expansion-mode-alist' is a plain alist keyed by
name, and dropping an entry only removes the menu item: nothing else
holds the name, and a display can still be selected from elisp."
  (setq speedbar-initial-expansion-mode-alist
        (seq-remove (lambda (entry)
                      (member (car entry) '("files" "buffers"
                                            "quick buffers")))
                    speedbar-initial-expansion-mode-alist)))

;; --- pr-review changed-files tree -----------------------------------
;; Speedbar's localized-display convention: for a buffer in
;; `pr-review-mode' it looks up the symbol `pr-review-speedbar-buttons'
;; and, when defined, fills the speedbar by calling it instead of
;; rendering a directory.  The function name is therefore fixed by
;; speedbar, not chosen here.

(defvar-local ch/speedbar--pr-signature nil
  "Signature (BUFFER . FILES) of the PR tree currently rendered.
Local to the speedbar buffer; a render is skipped while it matches.")

(defun pr-review-speedbar-buttons (buffer)
  "Fill the speedbar with BUFFER's changed files as a sparse tree.
Directories appear only as needed to position the changed files;
single-child directory chains are compressed into one entry."
  (let* ((files (sort (with-current-buffer buffer
                        (pr-review--find-all-file-names))
                      #'string<))
         (signature (cons buffer files)))
    ;; Speedbar calls this on every update pass and expects it to
    ;; decide for itself whether to redraw; redrawing would throw away
    ;; manual collapse state.  The text property distinguishes our
    ;; tree from directory contents another flavor left behind.
    (unless (and (equal ch/speedbar--pr-signature signature)
                 (> (buffer-size) 0)
                 (get-text-property (point-min) 'ch/speedbar-pr-tree))
      (require 'nerd-icons)
      (setq ch/speedbar--pr-signature signature)
      (erase-buffer)
      (insert (propertize (nerd-icons-octicon "nf-oct-git_pull_request")
                          'ch/speedbar-pr-tree t)
              " "
              (propertize (with-current-buffer buffer
                            (apply #'format "%s/%s#%s" pr-review--pr-path))
                          'face 'speedbar-directory-face)
              "\n")
      (ch/speedbar--pr-insert-nodes
       (ch/speedbar--pr-tree
        (mapcar (lambda (file) (cons (split-string file "/") file)) files))
       buffer 0))))

(defun ch/speedbar--pr-tree (entries)
  "Group ENTRIES, a list of (PARTS . PATH), into a rendering tree.
Return a list of (dir NAME CHILDREN) and (file NAME PATH) nodes,
directories first.  A directory holding a single subdirectory and no
files collapses into its child as one \"parent/child\" node."
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
                     (children (ch/speedbar--pr-tree (nreverse (cdr group)))))
                 (while (and (null (cdr children))
                             (eq (caar children) 'dir))
                   (setq name (concat name "/" (nth 1 (car children)))
                         children (nth 2 (car children))))
                 (list 'dir name children)))
             (nreverse groups))
     (nreverse files))))

(defun ch/speedbar--glyph-line (glyph &optional previous)
  "Render the current line's expander (or file marker) as GLYPH.
With PREVIOUS non-nil, act on the line before point (where
`speedbar-make-tag-line' leaves point after inserting).  The glyph is
a `display' property over the {+}/{-}/> button text, the same overlay
pattern speedbar's image mode uses: the buffer text keeps the shapes
that `speedbar-edit-line', `speedbar-toggle-line-expansion', and
`speedbar-change-expand-button-char' match on, so only the rendering
changes.  A separate inserted icon character would instead sit where
`speedbar-edit-line' expects the tag text and leave RET dead."
  (save-excursion
    (when previous (forward-line -1))
    (beginning-of-line)
    (when (re-search-forward "^[0-9]+: *\\({[-+]}\\|>\\)"
                             (line-end-position) t)
      (speedbar-with-writable
        (put-text-property (match-beginning 1) (match-end 1)
                           'display glyph)))))

(defun ch/speedbar--dir-glyph (open)
  "The directory glyph: an open folder when OPEN, else a closed one.
One consistent pair for every directory, standing in for {-}/{+}."
  (nerd-icons-faicon (if open "nf-fa-folder_open" "nf-fa-folder")))

(defun ch/speedbar--pr-insert-nodes (nodes buffer depth)
  "Insert tag lines for NODES at DEPTH; file lines jump into BUFFER.
Directories start expanded (the tree is sparse already) and contract
through the standard expansion button, so TAB and the evil z-fold
keys work on them."
  (dolist (node nodes)
    (pcase-exhaustive node
      (`(dir ,name ,children)
       (speedbar-make-tag-line 'curly ?- #'ch/speedbar--pr-dir-expand
                               (list children buffer)
                               name nil nil 'speedbar-directory-face depth)
       (ch/speedbar--glyph-line (ch/speedbar--dir-glyph t) t)
       (ch/speedbar--pr-insert-nodes children buffer (1+ depth)))
      (`(file ,name ,path)
       (speedbar-make-tag-line nil nil nil nil
                               name #'ch/speedbar--pr-file-visit
                               (cons path buffer)
                               'speedbar-file-face depth)
       (ch/speedbar--glyph-line (nerd-icons-icon-for-file name) t)))))

(defun ch/speedbar--pr-dir-expand (text token indent)
  "Expand or contract a PR-tree directory (speedbar button contract).
TEXT is the activated button's text ({+} or {-}), TOKEN is
(CHILDREN BUFFER), INDENT the line's depth."
  (cond
   ((string-search "+" text)
    (speedbar-change-expand-button-char ?-)
    (ch/speedbar--glyph-line (ch/speedbar--dir-glyph t))
    (speedbar-with-writable
      (save-excursion
        (end-of-line)
        (forward-char 1)
        (ch/speedbar--pr-insert-nodes (nth 0 token) (nth 1 token)
                                      (1+ indent)))))
   ((string-search "-" text)
    (speedbar-change-expand-button-char ?+)
    (ch/speedbar--glyph-line (ch/speedbar--dir-glyph nil))
    (speedbar-delete-subblock indent))))

(defun ch/speedbar--pr-file-visit (_text token _indent)
  "Jump to the diff section for the chosen PR-tree file.
TOKEN is (PATH . BUFFER)."
  (let ((path (car token))
        (buffer (cdr token)))
    (if (not (buffer-live-p buffer))
        (message "The PR buffer this tree was built from is gone")
      (pop-to-buffer buffer)
      (pr-review-goto-file path))))

(defun ch/speedbar--pr-file-at-point ()
  "Changed-file path whose section contains point, or nil.
Walks up from the magit section at point to the enclosing file
section."
  (when-let* ((section (magit-current-section)))
    (while (and section (not (magit-file-section-p section)))
      (setq section (slot-value section 'parent)))
    (when section (slot-value section 'value))))

(defun ch/speedbar--pr-file-position (file)
  "Position of FILE's line in the PR tree, or nil while collapsed.
Runs in the speedbar buffer; file lines carry (PATH . BUFFER) as
their speedbar token, directory lines a list, so only files match."
  (save-excursion
    (goto-char (point-min))
    (when-let* ((match (text-property-search-forward
                        'speedbar-token file
                        (lambda (target value)
                          (and (consp value)
                               (equal (car value) target))))))
      (prop-match-beginning match))))

(defun ch/speedbar--pr-point-follow ()
  "Move the PR tree's point to the file whose diff contains point.
On the buffer-local `post-command-hook' of pr-review buffers; a
no-op unless the PR tree is showing or while the file is unchanged."
  (when (and (featurep 'speedbar)
             (eq ch/speedbar--flavor 'pr)
             (eq (speedbar-frame-or-window) 'window))
    (let ((file (ch/speedbar--pr-file-at-point)))
      (when (and file (not (equal file ch/speedbar--pr-followed-file)))
        (setq ch/speedbar--pr-followed-file file)
        (when-let* ((window (get-buffer-window speedbar-buffer))
                    (position (with-current-buffer speedbar-buffer
                                (ch/speedbar--pr-file-position file))))
          (set-window-point window position))))))

(defun ch/speedbar--pr-arm-follow ()
  "Arm PR-tree point-following in this pr-review buffer."
  (add-hook 'post-command-hook #'ch/speedbar--pr-point-follow nil t))

(add-hook 'pr-review-mode-hook #'ch/speedbar--pr-arm-follow)

(with-eval-after-load 'evil
  ;; The b, f, p and g prefixes are titled by their own bundles.
  (evil-global-set-key 'motion (kbd "<leader> b t") #'ch/speedbar-buffers-tree)
  (evil-global-set-key 'motion (kbd "<leader> f t") #'ch/speedbar-outline-tree)
  (evil-global-set-key 'motion (kbd "<leader> p t") #'ch/speedbar-project-tree)
  (with-eval-after-load 'pr-review
    (evil-define-key 'motion pr-review-mode-map
      (kbd "<leader> g t") #'ch/speedbar-pr-tree)))
