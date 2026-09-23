;;; render-dwim-ert.el --- Tests for render-dwim -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Batch-run with -L pointing at the render-dwim package (parenting-ert
;; precedent).  Covers the candidate extraction (fence pairing, block
;; indent stripping, file references), the source normalization the
;; content-addressed cache names depend on, and the render and detect
;; paths end to end when merman-cli is on PATH (the flake check
;; arranges that).

;;; Code:

(require 'ert)
(require 'render-dwim)

(defmacro ch-render-dwim-tests--with-buffer (content &rest body)
  "Run BODY in a temp buffer holding CONTENT, point at the ^ marker.
The marker itself is removed."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,content)
     (goto-char (point-min))
     (search-forward "^")
     (delete-char -1)
     ,@body))

(ert-deftest ch-render-dwim-fence-at-point ()
  "Point inside a fenced block yields its info string and body."
  (ch-render-dwim-tests--with-buffer
      "prose\n```mermaid\ngraph TD\n  A-->^B\n```\nmore prose\n"
    (let ((fence (render-dwim--fence-at-point)))
      (should (equal (car fence) "mermaid"))
      (should (equal (render-dwim--clean (cdr fence))
                     "graph TD\n  A-->B\n")))))

(ert-deftest ch-render-dwim-fence-on-fence-lines ()
  "The opening and closing fence lines count as inside the block."
  (ch-render-dwim-tests--with-buffer "^```dot\ndigraph {}\n```\n"
    (should (equal (car (render-dwim--fence-at-point)) "dot")))
  (ch-render-dwim-tests--with-buffer "```dot\ndigraph {}\n^```\n"
    (should (equal (car (render-dwim--fence-at-point)) "dot"))))

(ert-deftest ch-render-dwim-fence-between-blocks-is-nil ()
  "A closing fence above point is not mistaken for an opener."
  (ch-render-dwim-tests--with-buffer
      "```mermaid\ngraph TD\n```\nbet^ween\n```mermaid\npie\n```\n"
    (should-not (render-dwim--fence-at-point))))

(ert-deftest ch-render-dwim-plain-fence-has-empty-lang ()
  "An info-string-less fence comes back with an empty LANG."
  (ch-render-dwim-tests--with-buffer "```\ngraph ^TD\n```\n"
    (should (equal (car (render-dwim--fence-at-point)) ""))))

(ert-deftest ch-render-dwim-block-around-point-strips-indent ()
  "The blank-line-delimited block loses its common indentation."
  (ch-render-dwim-tests--with-buffer
      "before\n\n  graph TD\n    A--^>B\n\nafter\n"
    (should (equal (render-dwim--clean (render-dwim--block-around-point))
                   "graph TD\n  A-->B\n")))
  (ch-render-dwim-tests--with-buffer "text\n^\ntext\n"
    (should-not (render-dwim--block-around-point))))

(ert-deftest ch-render-dwim-clean-normalizes-trailing-newlines ()
  "Cleaning yields exactly one trailing newline (cache-name parity)."
  (should (equal (render-dwim--clean "a\nb") "a\nb\n"))
  (should (equal (render-dwim--clean "a\nb\n\n\n") "a\nb\n")))

(ert-deftest ch-render-dwim-cache-file-is-content-addressed ()
  "Same source, same name; different source, different name."
  (let ((render-dwim-cache-directory
         (make-temp-file "render-dwim-ert" t)))
    (let ((a (render-dwim--cache-file "graph TD\n"))
          (a2 (render-dwim--cache-file "graph TD\n"))
          (b (render-dwim--cache-file "pie\n")))
      (should (equal a a2))
      (should-not (equal a b))
      (should (string-suffix-p ".svg" a))
      (should (eql (length (file-name-base a)) 12)))))

(ert-deftest ch-render-dwim-file-at-point ()
  "An image path at point is found; a ghostel :LINE tail is dropped."
  (let ((file (make-temp-file "render-dwim-ert" nil ".svg")))
    (unwind-protect
        (ch-render-dwim-tests--with-buffer
            (concat "diagram: " file ":1 tra^iling")
          (goto-char (point-min))
          (search-forward "diagram: ")
          (should (equal (render-dwim--file-at-point) file)))
      (delete-file file)))
  (ch-render-dwim-tests--with-buffer "/does/not/exist.sv^g:1\n"
    (should-not (render-dwim--file-at-point))))

(ert-deftest ch-render-dwim-render-mermaid-end-to-end ()
  "A render lands a label-legible SVG in the cache and reuses it."
  (skip-unless (executable-find (car render-dwim-mermaid-command)))
  (let ((render-dwim-cache-directory
         (make-temp-file "render-dwim-ert" t)))
    (let ((svg (render-dwim--render-mermaid "graph TD\n  A-->|edge| B\n")))
      (should (file-exists-p svg))
      (with-temp-buffer
        (insert-file-contents svg)
        (should (string-match-p "<text" (buffer-string)))
        (should-not (string-match-p "foreignObject" (buffer-string))))
      ;; The second call must not re-render: mtime stays put.
      (let ((mtime (file-attribute-modification-time
                    (file-attributes svg))))
        (should (equal (render-dwim--render-mermaid
                        "graph TD\n  A-->|edge| B\n")
                       svg))
        (should (equal (file-attribute-modification-time
                        (file-attributes svg))
                       mtime))))))

(ert-deftest ch-render-dwim-render-failure-is-legible ()
  "A broken diagram signals the renderer's own message."
  (skip-unless (executable-find (car render-dwim-mermaid-command)))
  (let ((render-dwim-cache-directory
         (make-temp-file "render-dwim-ert" t)))
    (let ((err (should-error (render-dwim--render-mermaid "graph TD\n  A-->\n")
                             :type 'user-error)))
      (should (string-match-p "render failed"
                              (error-message-string err))))))

(ert-deftest ch-render-dwim-detection-gates-bare-source ()
  "The detector accepts mermaid source and refuses prose."
  (skip-unless (executable-find (car render-dwim-detect-command)))
  (let ((render-dwim-cache-directory
         (make-temp-file "render-dwim-ert" t)))
    (should (file-exists-p
             (render-dwim--render-detected "sequenceDiagram\n  A->>B: hi\n")))
    (should-error (render-dwim--render-detected "plain prose here\n")
                  :type 'user-error)))

(provide 'render-dwim-ert)
;;; render-dwim-ert.el ends here
