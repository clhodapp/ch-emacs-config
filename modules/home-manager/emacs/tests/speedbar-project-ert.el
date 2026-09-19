;;; speedbar-project-ert.el --- Tests for the speedbar project tree -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Runs against the fully loaded init (load-init.el first), because what
;; these cover is how the Project tree's own rendering, evil, and
;; `context-menu-mode' combine: none of it is visible to a check that only
;; loads the init.  The deletion commands read a line's path out of the
;; speedbar token, which the tree hangs in a different place for a
;; directory (on the expander button) than for a file (on the name), and
;; which the config's glyph rendering covers with a `display' property.
;; `speedbar-line-token' misses both cases, so a regression there is
;; silent: the tree renders and the command simply never finds a file.

;;; Code:

(require 'ert)

(defvar ch-speedbar-tests--root nil
  "Temporary project the tree under test is rooted at.")

(defun ch-speedbar-tests--state-dir ()
  "Redirect state files the init points at the read-only store."
  (let ((dir (make-temp-file "ch-speedbar-tests-state" t)))
    (setq project-list-file (expand-file-name "projects.eld" dir)
          recentf-save-file (expand-file-name "recentf.eld" dir)
          savehist-file (expand-file-name "savehist.eld" dir))))

(defun ch-speedbar-tests--project ()
  "Build a throwaway project and open the Project tree on it.
The .git directory is what makes `project-current' recognize it."
  (ch-speedbar-tests--state-dir)
  (setq ch-speedbar-tests--root (make-temp-file "ch-speedbar-tests" t))
  (make-directory (expand-file-name "sub" ch-speedbar-tests--root))
  (make-directory (expand-file-name ".git" ch-speedbar-tests--root) t)
  (write-region "a\n" nil
                (expand-file-name "alpha.txt" ch-speedbar-tests--root))
  (write-region "b\n" nil
                (expand-file-name "beta.txt" ch-speedbar-tests--root))
  (write-region "c\n" nil
                (expand-file-name "sub/gamma.txt" ch-speedbar-tests--root))
  (with-temp-buffer
    (setq default-directory
          (file-name-as-directory ch-speedbar-tests--root))
    (ch/speedbar-project-tree)))

(defun ch-speedbar-tests--in (name)
  "Absolute path of NAME inside the test project."
  (expand-file-name name ch-speedbar-tests--root))

(defmacro ch-speedbar-tests--on-line (regexp &rest body)
  "Run BODY in the speedbar buffer with point at REGEXP's line start."
  (declare (indent 1))
  `(with-current-buffer speedbar-buffer
     (goto-char (point-min))
     (should (re-search-forward ,regexp nil t))
     (beginning-of-line)
     ,@body))

(defun ch-speedbar-tests--menu-keys ()
  "Keys of the context menu built for a press at point.
Goes through `context-menu-map', the same entry point a real press
uses, so the buffer-local contribution and the gating are both
exercised."
  (let* ((position (point))
         (window (get-buffer-window speedbar-buffer))
         (click (list 'down-mouse-3
                      (list window position '(0 . 0) 0 nil position)))
         (menu (context-menu-map click))
         (keys nil))
    (map-keymap (lambda (key _) (push key keys)) menu)
    (nreverse keys)))

(ert-deftest ch-speedbar-project-token-on-both-line-kinds ()
  "A file line and a directory line both yield their path.
`speedbar-line-token' finds neither: a directory's token sits on the
expander button rather than the name, and a file line's \">\" marker
is not the bracketed button its regexp requires."
  (ch-speedbar-tests--project)
  (ch-speedbar-tests--on-line "alpha\\.txt"
    (should (equal (ch/speedbar--project-entry-at)
                   (cons (ch-speedbar-tests--in "alpha.txt") nil))))
  (ch-speedbar-tests--on-line "^0:{\\+} sub"
    (should (equal (ch/speedbar--project-entry-at)
                   (cons (ch-speedbar-tests--in "sub") t)))))

(ert-deftest ch-speedbar-project-root-line-has-no-entry ()
  "The line naming the project itself offers nothing to delete."
  (ch-speedbar-tests--project)
  (with-current-buffer speedbar-buffer
    (goto-char (point-min))
    (should-not (ch/speedbar--project-entry-at))))

(ert-deftest ch-speedbar-project-delete-key-reaches-command ()
  "D in the tree runs the delete command rather than evil's D.
Evil's state keymaps outrank a speedbar specialized keymap, so a
plain `define-key' would lose to `evil-delete-line'."
  (ch-speedbar-tests--project)
  (with-current-buffer speedbar-buffer
    (should (eq (key-binding (kbd "D")) 'ch/speedbar--project-delete))))

(ert-deftest ch-speedbar-project-delete-file ()
  "Deleting a file removes it and drops only its line."
  (ch-speedbar-tests--project)
  (ch-speedbar-tests--on-line "alpha\\.txt"
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
      (call-interactively #'ch/speedbar--project-delete)))
  (should-not (file-exists-p (ch-speedbar-tests--in "alpha.txt")))
  (with-current-buffer speedbar-buffer
    (let ((text (buffer-string)))
      (should-not (string-match-p "alpha\\.txt" text))
      (should (string-match-p "beta\\.txt" text))
      (should (string-match-p "sub" text)))))

(ert-deftest ch-speedbar-project-delete-declined ()
  "Answering no leaves the file and the tree alone."
  (ch-speedbar-tests--project)
  (ch-speedbar-tests--on-line "beta\\.txt"
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
      (call-interactively #'ch/speedbar--project-delete)))
  (should (file-exists-p (ch-speedbar-tests--in "beta.txt")))
  (with-current-buffer speedbar-buffer
    (should (string-match-p "beta\\.txt" (buffer-string)))))

(ert-deftest ch-speedbar-project-delete-directory-says-recursive ()
  "A directory's prompt states that the contents go too."
  (ch-speedbar-tests--project)
  (let (prompt)
    (ch-speedbar-tests--on-line "^0:{\\+} sub"
      (cl-letf (((symbol-function 'yes-or-no-p)
                 (lambda (question &rest _) (setq prompt question) t)))
        (call-interactively #'ch/speedbar--project-delete)))
    (should (string-match-p "directory and its contents" prompt)))
  (should-not (file-exists-p (ch-speedbar-tests--in "sub"))))

(ert-deftest ch-speedbar-project-delete-kills-visiting-buffer ()
  "A buffer visiting the deleted file goes with it.
Left alive it would offer to write the file back."
  (ch-speedbar-tests--project)
  (let ((visiting (find-file-noselect (ch-speedbar-tests--in "beta.txt"))))
    (should (buffer-live-p visiting))
    (ch-speedbar-tests--on-line "beta\\.txt"
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
        (call-interactively #'ch/speedbar--project-delete)))
    (should-not (buffer-live-p visiting))))

(ert-deftest ch-speedbar-project-context-menu-offers-delete ()
  "A press on a file or directory line gains a Delete entry."
  (ch-speedbar-tests--project)
  (ch-speedbar-tests--on-line "alpha\\.txt"
    (should (memq 'ch/speedbar-project-delete
                  (ch-speedbar-tests--menu-keys))))
  (ch-speedbar-tests--on-line "^0:{\\+} sub"
    (should (memq 'ch/speedbar-project-delete
                  (ch-speedbar-tests--menu-keys)))))

(ert-deftest ch-speedbar-project-context-menu-gated ()
  "The entry stays out of the root line and of the other trees.
All four trees share one speedbar buffer, so the contribution has to
gate on the showing flavor rather than on the buffer."
  (ch-speedbar-tests--project)
  (with-current-buffer speedbar-buffer
    (goto-char (point-min))
    (should-not (memq 'ch/speedbar-project-delete
                      (ch-speedbar-tests--menu-keys))))
  (with-temp-buffer
    (setq default-directory
          (file-name-as-directory ch-speedbar-tests--root))
    (ch/speedbar-buffers-tree))
  (with-current-buffer speedbar-buffer
    (goto-char (point-min))
    (should-not (memq 'ch/speedbar-project-delete
                      (ch-speedbar-tests--menu-keys)))))

(provide 'speedbar-project-ert)
;;; speedbar-project-ert.el ends here
