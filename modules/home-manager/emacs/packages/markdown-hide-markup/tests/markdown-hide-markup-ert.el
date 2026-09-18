;;; markdown-hide-markup-ert.el --- Tests for markdown-hide-markup -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Batch-run with the wrapped scope emacs: package activation puts the
;; markdown tree-sitter grammars on `treesit-extra-load-path', which
;; `markdown-ts-mode' needs; the package under test loads from the -L'd
;; source directory.
;;
;; The assertions read the `invisible' text property rather than
;; anything about rendering, because that property plus the buffer's
;; invisibility spec is exactly what decides whether a character is
;; displayed.  A helper turns the pair into the string a reader would
;; see, so the expectations below are written as visible text.

;;; Code:

(require 'ert)

(package-activate-all)

(require 'markdown-ts-mode)
(require 'markdown-hide-markup)

(defun markdown-hide-markup-tests--visible ()
  "Return the current buffer's text minus what the spec hides."
  (let ((out nil)
        (pos (point-min)))
    (while (< pos (point-max))
      (let ((next (next-single-property-change pos 'invisible nil (point-max)))
            (prop (get-text-property pos 'invisible)))
        (unless (and prop (invisible-p prop))
          (push (buffer-substring-no-properties pos next) out))
        (setq pos next)))
    (apply #'concat (nreverse out))))

(defmacro markdown-hide-markup-tests--with (text &rest body)
  "Run BODY in a `markdown-ts-mode' buffer holding TEXT, point at start.
BODY is responsible for fontifying: whether markup carries the
invisible property depends on `markdown-ts-hide-markup' at the
moment font-lock runs, and `font-lock-ensure' will not redo a
region it has already done."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (goto-char (point-min))
     (markdown-ts-mode)
     ,@body))

(defun markdown-hide-markup-tests--visible-now ()
  "Fontify, then return the visible text."
  (font-lock-flush)
  (font-lock-ensure)
  (markdown-hide-markup--update)
  (markdown-hide-markup-tests--visible))

(defun markdown-hide-markup-tests--at (pos)
  "Move to POS, refresh, and return visible text."
  (goto-char pos)
  (markdown-hide-markup-tests--visible-now))

(ert-deftest markdown-hide-markup-hides-heading-hashes ()
  "Enabling the mode hides a heading's leading hashes."
  (markdown-hide-markup-tests--with "## Title\n\nbody text\n"
    (let ((markdown-hide-markup-reveal nil))
      (markdown-hide-markup-mode 1)
      (should (equal (markdown-hide-markup-tests--visible-now)
                     "Title\n\nbody text\n")))))

(ert-deftest markdown-hide-markup-hides-emphasis-markers ()
  "Emphasis and strong-emphasis markers stop being displayed."
  (markdown-hide-markup-tests--with "a *soft* and **loud** word\n"
    (let ((markdown-hide-markup-reveal nil))
      (markdown-hide-markup-mode 1)
      (should (equal (markdown-hide-markup-tests--visible-now)
                     "a soft and loud word\n")))))

(ert-deftest markdown-hide-markup-hides-code-span-and-link ()
  "Backticks go, and a link keeps its text without brackets or URL."
  (markdown-hide-markup-tests--with "see `code` and [text](https://example.com)\n"
    (let ((markdown-hide-markup-reveal nil))
      (markdown-hide-markup-mode 1)
      (should (equal (markdown-hide-markup-tests--visible-now)
                     "see code and text\n")))))

(ert-deftest markdown-hide-markup-buffer-text-is-untouched ()
  "Hiding changes display only; the buffer's characters are all there."
  (let ((source "## Title\n\na *soft* word\n"))
    (markdown-hide-markup-tests--with source
      (markdown-hide-markup-mode 1)
      (markdown-hide-markup-tests--visible-now)
      (should (equal (buffer-substring-no-properties (point-min) (point-max))
                     source)))))

(ert-deftest markdown-hide-markup-disabling-restores-markup ()
  "Turning the mode off shows every delimiter again."
  (let ((source "## Title\n\na *soft* word\n"))
    (markdown-hide-markup-tests--with source
      (markdown-hide-markup-mode 1)
      (markdown-hide-markup-mode -1)
      (should (equal (markdown-hide-markup-tests--visible-now) source)))))

(ert-deftest markdown-hide-markup-reveals-construct-at-point ()
  "Point inside emphasis shows that construct's markers and no others."
  (markdown-hide-markup-tests--with "a *soft* and **loud** word\n"
    (markdown-hide-markup-mode 1)
    (should (equal (markdown-hide-markup-tests--at (+ (point-min) 4))
                   "a *soft* and loud word\n"))))

(ert-deftest markdown-hide-markup-rehides-when-point-leaves ()
  "Moving out of a construct hides its markers again."
  (markdown-hide-markup-tests--with "a *soft* and **loud** word\n"
    (markdown-hide-markup-mode 1)
    (markdown-hide-markup-tests--at (+ (point-min) 4))
    (should (equal (markdown-hide-markup-tests--at (+ (point-min) 16))
                   "a soft and **loud** word\n"))))

(ert-deftest markdown-hide-markup-reveals-heading-at-point ()
  "Point in a heading reveals its hashes, leaving other blocks hidden."
  (markdown-hide-markup-tests--with "## Title\n\n### Other\n"
    (markdown-hide-markup-mode 1)
    (should (equal (markdown-hide-markup-tests--at (+ (point-min) 4))
                   "## Title\n\nOther\n"))))

(ert-deftest markdown-hide-markup-reveal-line-takes-whole-line ()
  "With `line' reveal, every construct on point's line is shown."
  (markdown-hide-markup-tests--with "a *soft* and **loud** word\n\n*other*\n"
    (let ((markdown-hide-markup-reveal 'line))
      (markdown-hide-markup-mode 1)
      (should (equal (markdown-hide-markup-tests--at (+ (point-min) 4))
                     "a *soft* and **loud** word\n\nother\n")))))

(ert-deftest markdown-hide-markup-reveal-nil-never-reveals ()
  "With reveal disabled, point inside a construct changes nothing."
  (markdown-hide-markup-tests--with "a *soft* word\n"
    (let ((markdown-hide-markup-reveal nil))
      (markdown-hide-markup-mode 1)
      (should (equal (markdown-hide-markup-tests--at (+ (point-min) 4))
                     "a soft word\n")))))

(ert-deftest markdown-hide-markup-refuses-outside-markdown ()
  "The mode errors rather than half-enabling in a non-Markdown buffer."
  (with-temp-buffer
    (text-mode)
    (should-error (markdown-hide-markup-mode 1) :type 'user-error)
    (should-not markdown-hide-markup-mode)))

(ert-deftest markdown-hide-markup-mode-maybe-is-hook-safe ()
  "The hook entry enables in Markdown and stays quiet elsewhere."
  (with-temp-buffer
    (text-mode)
    (markdown-hide-markup-mode-maybe)
    (should-not markdown-hide-markup-mode))
  (markdown-hide-markup-tests--with "# Title\n"
    (markdown-hide-markup-mode-maybe)
    (should markdown-hide-markup-mode)))

(provide 'markdown-hide-markup-ert)
;;; markdown-hide-markup-ert.el ends here
