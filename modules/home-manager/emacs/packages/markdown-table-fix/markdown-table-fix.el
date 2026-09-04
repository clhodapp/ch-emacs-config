;;; markdown-table-fix --- Realign markdown pipe tables via tree-sitter -*- lexical-binding: t -*-
;; SPDX-License-Identifier: MIT
;;; Commentary:
;;
;; Rewrites GFM pipe tables into canonical form: one space of padding
;; around every cell, columns padded to the widest cell (display width,
;; so wide characters count double), delimiter rules regenerated at
;; column width with the alignment colons preserved, outer pipes added
;; where missing, and short rows padded with empty cells.  Table
;; structure comes from the tree-sitter markdown grammar (pipe_table
;; nodes), not from regexps.
;;
;; Grammar wrinkles this leans on: an empty interior cell (`||') is not
;; a cell node — the second pipe surfaces as an ERROR node whose text is
;; "|", so cell slots are reconstructed by walking a row's pipe tokens;
;; and in indented contexts the pipe_table node starts after the first
;; line's indentation but *contains* the interior lines' indentation.
;;
;;; Code:

(require 'seq)
(require 'subr-x)
(require 'treesit)

(defconst markdown-table-fix--row-types
  '("pipe_table_header" "pipe_table_delimiter_row" "pipe_table_row")
  "Node types of pipe table children that carry cells.")

(defconst markdown-table-fix--cell-types
  '("pipe_table_cell" "pipe_table_delimiter_cell")
  "Node types that hold a cell's content.")

(defun markdown-table-fix--row-slots (row)
  "Return ROW's cell nodes in column order, nil for empty cells.
A pipe token that directly follows another pipe token closes an
empty cell slot.  Content before the first pipe or after the last
one is a cell only when the grammar produced a cell node for it.
Signal `user-error' if ROW holds content this walk cannot place."
  (let (slots pending)
    (dolist (child (treesit-node-children row))
      (let ((text (treesit-node-text child t)))
        (cond
         ;; Pipe separators; ERROR-wrapped interior pipes match by text.
         ((equal text "|")
          (when pending (push nil slots))
          (setq pending t))
         ((member (treesit-node-type child) markdown-table-fix--cell-types)
          (push child slots)
          (setq pending nil))
         ((string-blank-p text))
         (t (user-error "Unrecognized pipe table row structure: %S" text)))))
    (nreverse slots)))

(defun markdown-table-fix--alignment (cell)
  "Return the alignment of delimiter CELL: `left', `right', `center', nil."
  (when cell
    (let ((kinds (mapcar #'treesit-node-type (treesit-node-children cell))))
      (cond
       ((and (member "pipe_table_align_left" kinds)
             (member "pipe_table_align_right" kinds))
        'center)
       ((member "pipe_table_align_left" kinds) 'left)
       ((member "pipe_table_align_right" kinds) 'right)))))

(defun markdown-table-fix--pad (text width align)
  "Pad TEXT with spaces to display width WIDTH per ALIGN."
  (let* ((pad (max 0 (- width (string-width text))))
         (left (pcase align
                 ('right pad)
                 ('center (/ pad 2))
                 (_ 0))))
    (concat (make-string left ?\s) text (make-string (- pad left) ?\s))))

(defun markdown-table-fix--rule (width align)
  "Return a delimiter rule of display width WIDTH for ALIGN."
  (pcase align
    ('left (concat ":" (make-string (1- width) ?-)))
    ('right (concat (make-string (1- width) ?-) ":"))
    ('center (concat ":" (make-string (- width 2) ?-) ":"))
    (_ (make-string width ?-))))

(defun markdown-table-fix--render (table)
  "Return the canonical text of pipe table node TABLE, sans indentation.
Lines are joined with bare newlines; the caller owns indentation
and the trailing newline."
  (let* ((rows (seq-filter
                (lambda (n)
                  (member (treesit-node-type n)
                          markdown-table-fix--row-types))
                (treesit-node-children table)))
         (row-slots (mapcar #'markdown-table-fix--row-slots rows))
         (ncols (apply #'max (mapcar #'length row-slots)))
         (delimiter-p (lambda (row)
                        (equal (treesit-node-type row)
                               "pipe_table_delimiter_row")))
         (aligns
          (let ((delim (seq-find delimiter-p rows)))
            (and delim
                 (mapcar #'markdown-table-fix--alignment
                         (markdown-table-fix--row-slots delim)))))
         (cell-text (lambda (slot)
                      (if slot (string-trim (treesit-node-text slot t)) "")))
         (widths
          (mapcar
           (lambda (col)
             (apply #'max 3
                    (seq-map-indexed
                     (lambda (slots row-index)
                       (if (funcall delimiter-p (nth row-index rows))
                           0
                         (string-width
                          (funcall cell-text (nth col slots)))))
                     row-slots)))
           (number-sequence 0 (1- ncols)))))
    (string-join
     (seq-map-indexed
      (lambda (slots row-index)
        (let ((delimiter (funcall delimiter-p (nth row-index rows))))
          (concat
           "| "
           (string-join
            (mapcar
             (lambda (col)
               (let ((width (nth col widths))
                     (align (nth col aligns)))
                 (if delimiter
                     (markdown-table-fix--rule width align)
                   (markdown-table-fix--pad
                    (funcall cell-text (nth col slots)) width align))))
             (number-sequence 0 (1- ncols)))
            " | ")
           " |")))
      row-slots)
     "\n")))

(defun markdown-table-fix--check-children (table)
  "Signal `user-error' if TABLE has non-row children carrying content.
Rebuilding such a table from its rows would drop that content."
  (dolist (child (treesit-node-children table))
    (unless (member (treesit-node-type child)
                    (cons "block_continuation"
                          markdown-table-fix--row-types))
      (unless (string-blank-p (treesit-node-text child t))
        (user-error "Unrecognized pipe table structure: %S"
                    (treesit-node-text child t))))))

(defun markdown-table-fix--fix-node (table)
  "Replace pipe table node TABLE with its canonical form.
Interior lines are re-indented to the first line's indentation.
Return non-nil when the buffer changed."
  (markdown-table-fix--check-children table)
  (let* ((start (treesit-node-start table))
         (end (treesit-node-end table))
         (original (buffer-substring-no-properties start end))
         (indent (save-excursion
                   (goto-char start)
                   (buffer-substring-no-properties
                    (line-beginning-position) start)))
         (rendered (concat
                    (string-replace
                     "\n" (concat "\n" indent)
                     (markdown-table-fix--render table))
                    (and (string-suffix-p "\n" original) "\n"))))
    (unless (equal rendered original)
      (save-excursion
        (delete-region start end)
        (goto-char start)
        (insert rendered))
      t)))

(defun markdown-table-fix--table-at (pos parser)
  "Return the pipe table node of PARSER around POS, or nil."
  (treesit-parent-until
   (treesit-node-at pos parser)
   (lambda (node) (equal (treesit-node-type node) "pipe_table"))
   t))

;;;###autoload
(defun markdown-table-fix-dwim ()
  "Realign the pipe table at point, or all of the buffer's tables.
With point inside a pipe table only that table is rewritten;
anywhere else every pipe table in the buffer is."
  (interactive)
  (unless (treesit-ready-p 'markdown)
    (user-error "The markdown tree-sitter grammar is not available"))
  (let* ((parser (treesit-parser-create 'markdown))
         (at-point (markdown-table-fix--table-at (point) parser))
         (tables (if at-point
                     (list at-point)
                   (mapcar #'cdr
                           (treesit-query-capture
                            parser '((pipe_table) @table))))))
    (unless tables
      (user-error "No pipe table found"))
    ;; Rewrite back to front so pending node positions stay valid.
    (let ((total (length tables))
          (changed 0))
      (dolist (table (nreverse tables))
        (when (markdown-table-fix--fix-node table)
          (setq changed (1+ changed))))
      (message "%d table%s realigned, %d already canonical"
               changed (if (= changed 1) "" "s")
               (- total changed)))))

(provide 'markdown-table-fix)
;;; markdown-table-fix.el ends here
