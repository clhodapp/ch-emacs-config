;;; mode-line-ert.el --- Tests for the mode-line indicators -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; The mode-line indicators exist to show nothing in the normal case, so
;; the property worth testing is the empty string: a saved, writable,
;; local, UTF-8 buffer must contribute no characters to the left edge.
;; The rest of the tests pin what each deviation renders.
;;
;; These run against the assembled init package, the same artifact the
;; Home Manager module installs.  The indicator functions read only
;; buffer-local state and return strings, so a temp buffer under --batch
;; exercises them exactly as redisplay does; no frame is needed.  That
;; matters because `%z' and the end-of-line descriptor, which the stock
;; segments used, suppress themselves without a frame and cannot be
;; tested this way at all.

;;; Code:

(require 'ert)
(require 'ch-emacs-config-default)

(defmacro ch-mode-line-tests--with-buffer (setup &rest body)
  "Run BODY in a fresh temp buffer configured by SETUP.
`mode-line-format' is automatically buffer-local, and buffers made
before the init loads capture the stock value, so the local binding is
killed to make the buffer inherit the configured default."
  (declare (indent 1))
  `(with-temp-buffer
     (kill-local-variable 'mode-line-format)
     ,setup
     ,@body))

;;; The normal case contributes nothing.

(ert-deftest ch-mode-line-normal-buffer-has-no-status-icon ()
  "A saved, writable buffer shows no status glyph."
  (ch-mode-line-tests--with-buffer
      (progn (setq buffer-file-name "/tmp/notes.txt")
             (insert "text")
             (set-buffer-modified-p nil))
    (should (equal (ch-emacs-config--buffer-status-icon) ""))))

(ert-deftest ch-mode-line-local-buffer-has-no-remote-icon ()
  "A buffer on the local filesystem shows no remote glyph."
  (ch-mode-line-tests--with-buffer
      (setq default-directory "/tmp/")
    (should (equal (ch-emacs-config--remote-icon) ""))))

(ert-deftest ch-mode-line-utf8-unix-has-no-coding-tag ()
  "UTF-8 with Unix line endings is the default and says nothing."
  (ch-mode-line-tests--with-buffer
      (set-buffer-file-coding-system 'utf-8-unix)
    (should (equal (ch-emacs-config--coding-tag) ""))))

;;; Deviations render.

(ert-deftest ch-mode-line-unsaved-buffer-shows-an-icon ()
  "A file buffer with unsaved changes contributes a glyph."
  (ch-mode-line-tests--with-buffer
      (progn (setq buffer-file-name "/tmp/notes.txt")
             (insert "text")
             (set-buffer-modified-p t))
    (should-not (equal (ch-emacs-config--buffer-status-icon) ""))))

(ert-deftest ch-mode-line-read-only-buffer-shows-an-icon ()
  "A read-only buffer contributes a glyph."
  (ch-mode-line-tests--with-buffer
      (progn (setq buffer-file-name "/tmp/notes.txt")
             (setq buffer-read-only t))
    (should-not (equal (ch-emacs-config--buffer-status-icon) ""))))

(ert-deftest ch-mode-line-read-only-wins-over-modified ()
  "When a buffer is both read-only and modified, read-only is reported."
  (let (read-only-glyph both-glyph)
    (ch-mode-line-tests--with-buffer
        (progn (setq buffer-file-name "/tmp/notes.txt")
               (setq buffer-read-only t))
      (setq read-only-glyph (ch-emacs-config--buffer-status-icon)))
    (ch-mode-line-tests--with-buffer
        (progn (setq buffer-file-name "/tmp/notes.txt")
               (insert "text")
               (set-buffer-modified-p t)
               (setq buffer-read-only t))
      (setq both-glyph (ch-emacs-config--buffer-status-icon)))
    (should (equal read-only-glyph both-glyph))))

(ert-deftest ch-mode-line-buffer-without-a-file-is-never-unsaved ()
  "A modified buffer with no file behind it reports nothing.
Its modified flag tracks nothing a save would clear, so reporting it
would put a glyph on the scratch buffer and on process output."
  (ch-mode-line-tests--with-buffer
      (progn (insert "text") (set-buffer-modified-p t))
    (should (equal (ch-emacs-config--buffer-status-icon) ""))))

(ert-deftest ch-mode-line-remote-directory-shows-an-icon ()
  "A TRAMP directory contributes a glyph."
  (ch-mode-line-tests--with-buffer
      (setq default-directory "/ssh:host:/tmp/")
    (should-not (equal (ch-emacs-config--remote-icon) ""))))

;;; The coding tag names what differs, in words.

(ert-deftest ch-mode-line-crlf-is-named ()
  "A CRLF file is reported as CRLF rather than as \"(DOS)\"."
  (ch-mode-line-tests--with-buffer
      (set-buffer-file-coding-system 'utf-8-dos)
    (should (equal (ch-emacs-config--coding-tag) " CRLF"))))

(ert-deftest ch-mode-line-cr-is-named ()
  "A CR file is reported as CR."
  (ch-mode-line-tests--with-buffer
      (set-buffer-file-coding-system 'utf-8-mac)
    (should (equal (ch-emacs-config--coding-tag) " CR"))))

(ert-deftest ch-mode-line-non-utf8-coding-is-named ()
  "A non-UTF-8 encoding is named by its coding system."
  (ch-mode-line-tests--with-buffer
      (set-buffer-file-coding-system 'iso-latin-1-unix)
    (should (equal (ch-emacs-config--coding-tag) " iso-latin-1"))))

(ert-deftest ch-mode-line-coding-and-eol-both-deviating ()
  "Encoding and line ending are reported together, single-spaced."
  (ch-mode-line-tests--with-buffer
      (set-buffer-file-coding-system 'iso-latin-1-dos)
    (should (equal (ch-emacs-config--coding-tag) " iso-latin-1 CRLF"))))

(ert-deftest ch-mode-line-prefer-utf-8-counts-as-plain ()
  "Emacs picks prefer-utf-8 for many decoded files; it is not a deviation."
  (ch-mode-line-tests--with-buffer
      (set-buffer-file-coding-system 'prefer-utf-8-unix)
    (should (equal (ch-emacs-config--coding-tag) ""))))

(ert-deftest ch-mode-line-unibyte-buffer-is-quiet ()
  "Unibyte buffers are the internal process ones; encoding means nothing."
  (ch-mode-line-tests--with-buffer
      (set-buffer-multibyte nil)
    (should (equal (ch-emacs-config--coding-tag) ""))))

;;; The assembled format.

(ert-deftest ch-mode-line-format-drops-the-constant-segments ()
  "The rebuilt format omits the segments that never varied.
`mode-line-client' is among them because the daemon bundle runs Emacs as
a daemon: every frame with a window system is an emacsclient frame, so
its \"@\" was on every frame the user ever sees."
  (let ((format (default-value 'mode-line-format)))
    (should-not (memq 'mode-line-front-space format))
    (should-not (memq 'mode-line-frame-identification format))
    (should-not (memq 'mode-line-modified format))
    (should-not (memq 'mode-line-client format))))

(ert-deftest ch-mode-line-format-keeps-the-informative-segments ()
  "Position, major mode, version control and misc info stay."
  (let ((format (default-value 'mode-line-format)))
    (should (memq 'mode-line-position format))
    (should (memq 'mode-line-modes format))
    (should (memq 'mode-line-misc-info format))
    (should (assq 'vc-mode format))))

(ert-deftest ch-mode-line-minor-modes-collapse-with-exceptions ()
  "Lighters collapse except the two that vary per buffer."
  (should (equal mode-line-collapse-minor-modes '(not envrc-mode jinx-mode))))

;;; mode-line-ert.el ends here
