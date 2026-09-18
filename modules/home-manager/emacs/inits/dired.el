;; SPDX-License-Identifier: MIT
;; init dired

;; This bundle section compiles before evil's (alphabetical aggregation), so
;; the `evil-define-key' macro isn't known yet; load it for expansion.
(eval-when-compile
  (require 'dired)
  (require 'dired-aux)
  (require 'evil))

;; use-package's compile-time load runs inside `eval-when-compile', so the
;; byte compiler flags the functions behind the `evil-define-key' macro and
;; its bound commands as possibly missing at runtime; declare them.
(declare-function evil-define-key* "evil-core")
(declare-function dired-get-filename "dired")
(declare-function dired-get-subdir "dired")
(declare-function dired-goto-subdir "dired-aux")
(declare-function dired-kill-subdir "dired-aux")
(declare-function dired-maybe-insert-subdir "dired-aux")
(declare-function dired-find-file "dired")
(defvar dired-subdir-alist)

(defun ch/dired--subdir-at-point ()
  "The directory this dired line stands for, or nil.

On a subdirectory header line (the \"/path/to/dir:\" line of an
inserted listing) that is the directory the header names; on an
ordinary entry line for a directory it is that directory.  Any other
line, including the \"total\" line and blanks, gives nil.  The name
comes back expanded with a trailing slash, the form
`dired-subdir-alist' keys use."
  (or (dired-get-subdir)
      (let ((file (dired-get-filename nil t)))
        (and file
             (file-directory-p file)
             (file-name-as-directory (expand-file-name file))))))

(defun ch/dired--subdir-inserted-p (dir)
  "Whether DIR already has an inserted listing in this dired buffer.
DIR is expanded with a trailing slash, as `ch/dired--subdir-at-point'
returns it."
  (and (assoc dir dired-subdir-alist) t))

(defun ch/dired-close-subdir ()
  "Remove the inserted listing of the subdirectory at point.

This undoes `I' (`dired-maybe-insert-subdir').  Point on a directory
whose listing is open closes that listing, whether point sits on the
directory's entry line up in the parent or on the header line of the
listing itself; from an entry line point returns to it, so a following
`I' reopens what was just closed.  Anywhere else, including a file
line, it closes the listing that contains point, which is what vim's
`zc' does to the fold around the cursor.  Dired cannot remove the
buffer's own top-level listing, so that signals."
  (interactive)
  (let* ((dir (ch/dired--subdir-at-point))
         (open (and dir (ch/dired--subdir-inserted-p dir)))
         ;; Only meaningful when the listing being killed is somewhere
         ;; other than where point is: the kill deletes the region point
         ;; sits in, and a marker inside it would collapse to its start.
         (return-to (and open (not (dired-get-subdir)) (point-marker))))
    (unwind-protect
        (progn
          (when open
            (dired-goto-subdir dir))
          (dired-kill-subdir))
      (when return-to
        (goto-char return-to)
        (set-marker return-to nil)))))

(defun ch/dired-toggle-subdir ()
  "Insert the subdirectory at point, or close it if already inserted.

Opening is `I' (`dired-maybe-insert-subdir'); closing is
`ch/dired-close-subdir'.  On a line that is not a directory this
visits the file instead."
  (interactive)
  (let ((dir (ch/dired--subdir-at-point)))
    (cond
     ((null dir) (dired-find-file))
     ((ch/dired--subdir-inserted-p dir) (ch/dired-close-subdir))
     (t (dired-maybe-insert-subdir dir)))))

(defun ch/dired-mouse-toggle-subdir (event)
  "Run `ch/dired-toggle-subdir' on the line EVENT points at."
  (interactive "e")
  (let ((window (posn-window (event-end event)))
        (position (posn-point (event-end event))))
    (when (windowp window)
      (select-window window))
    (when (integerp position)
      (goto-char position)))
  (ch/dired-toggle-subdir))

(use-package dired
  :config
  ;; `a' (dired-find-alternate-file) is a fine bind here; drop the
  ;; disabled-command warning.
  (put 'dired-find-alternate-file 'disabled nil)

  ;; Stock dired leaves mouse-1 to Emacs's link-following, via a
  ;; [follow-link] binding of `mouse-face' that makes each filename count
  ;; as a link, so a quick click runs `dired-mouse-find-file-other-window'.
  ;; Clearing that entry needs `define-key' on `dired-mode-map' itself;
  ;; `evil-define-key' writes to an auxiliary map and would leave the
  ;; original in place.  The binding then goes where evil will find it:
  ;; evil-collection puts dired buffers in normal state, and its state
  ;; keymap outranks `dired-mode-map' (speedbar.el hit the same thing).
  ;; The repeat variants matter as much as the single press, because this
  ;; is a toggle: opening a directory and shutting it again lands two
  ;; clicks inside `double-click-time' and Emacs delivers the second as
  ;; `double-mouse-1'.  Unbound, it would do nothing and the toggle would
  ;; appear to swallow every other click.  Emacs caps its synthesized
  ;; repeat modifiers at triple, so these two cover four clicks and beyond.
  (define-key dired-mode-map [follow-link] nil)
  (evil-define-key 'normal dired-mode-map
    [mouse-1] #'ch/dired-mouse-toggle-subdir
    [double-mouse-1] #'ch/dired-mouse-toggle-subdir
    [triple-mouse-1] #'ch/dired-mouse-toggle-subdir
    ;; vim's fold mnemonics for the same open/close/toggle the mouse
    ;; drives: an inserted subdirectory listing is fold-shaped.  Evil
    ;; binds these globally to the hideshow/outline fold commands, which
    ;; have nothing to act on in a dired buffer; this auxiliary map
    ;; outranks that one only here, so folding elsewhere is unchanged.
    ;; `I' (evil-collection's `dired-maybe-insert-subdir') is untouched.
    "zo" #'dired-maybe-insert-subdir
    "zc" #'ch/dired-close-subdir
    "za" #'ch/dired-toggle-subdir))
