;;; markdown-table-fix-ert.el --- Tests for markdown-table-fix -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Batch-run with the wrapped scope emacs: package activation puts the
;; markdown tree-sitter grammar on `treesit-extra-load-path', which the
;; fixer needs; the package under test itself loads from the -L'd
;; source directory.

;;; Code:

(require 'ert)

(package-activate-all)

(require 'markdown-table-fix)

(defun markdown-table-fix-tests--fix (input &optional pos)
  "Run the fixer over INPUT with point at POS (default `point-min')."
  (with-temp-buffer
    (insert input)
    (goto-char (or pos (point-min)))
    (markdown-table-fix-dwim)
    (buffer-string)))

(ert-deftest markdown-table-fix-basic-realign ()
  "Columns pad to the widest cell; rules regenerate at column width."
  (should (equal (markdown-table-fix-tests--fix
                  "| a | bb |\n|-|-|\n| ccc | d |\n")
                 "| a   | bb  |\n| --- | --- |\n| ccc | d   |\n")))

(ert-deftest markdown-table-fix-alignment-preserved ()
  "Alignment colons survive and drive the cell padding side."
  (should (equal (markdown-table-fix-tests--fix
                  "| left | mid | right |\n|:--|:-:|--:|\n| a | b | c |\n")
                 (concat "| left | mid | right |\n"
                         "| :--- | :-: | ----: |\n"
                         "| a    |  b  |     c |\n"))))

(ert-deftest markdown-table-fix-empty-and-short-rows ()
  "Interior empty cells survive; short rows pad out with empty cells."
  (should (equal (markdown-table-fix-tests--fix
                  "| a | b | c |\n|---|---|---|\n| x || z |\n| only |\n")
                 (concat "| a    | b   | c   |\n"
                         "| ---- | --- | --- |\n"
                         "| x    |     | z   |\n"
                         "| only |     |     |\n"))))

(ert-deftest markdown-table-fix-outer-pipes-added ()
  "Rows written without outer pipes gain them."
  (should (equal (markdown-table-fix-tests--fix
                  "a | b\n--- | ---\n1 | 2\n")
                 "| a   | b   |\n| --- | --- |\n| 1   | 2   |\n")))

(ert-deftest markdown-table-fix-indented-table ()
  "Interior lines re-indent to the first line's indentation."
  (should (equal (markdown-table-fix-tests--fix
                  "- item\n\n  | h | i |\n    | :-: | - |\n   | 1 | 2 |\n")
                 (concat "- item\n\n"
                         "  |  h  | i   |\n"
                         "  | :-: | --- |\n"
                         "  |  1  | 2   |\n"))))

(ert-deftest markdown-table-fix-display-width ()
  "Wide characters count at display width, not character count."
  (should (equal (markdown-table-fix-tests--fix
                  "| 日本 | b |\n|---|---|\n| x | 語 |\n")
                 "| 日本 | b   |\n| ---- | --- |\n| x    | 語  |\n")))

(ert-deftest markdown-table-fix-escaped-pipe ()
  "Escaped pipes stay inside their cell."
  (should (equal (markdown-table-fix-tests--fix
                  "| a \\| b | c |\n|---|---|\n| 1 | 2 |\n")
                 "| a \\| b | c   |\n| ------ | --- |\n| 1      | 2   |\n")))

(ert-deftest markdown-table-fix-no-trailing-newline ()
  "A table ending the buffer without a newline stays newline-less."
  (should (equal (markdown-table-fix-tests--fix
                  "| a | b |\n|-|-|\n| 1 | 2 |")
                 "| a   | b   |\n| --- | --- |\n| 1   | 2   |")))

(ert-deftest markdown-table-fix-point-scopes-to-table ()
  "Point inside a table restricts the rewrite to that table."
  (should (equal (markdown-table-fix-tests--fix
                  "| a | b |\n|-|-|\n\n| c  | d |\n|-|-|\n" 3)
                 "| a   | b   |\n| --- | --- |\n\n| c  | d |\n|-|-|\n")))

(ert-deftest markdown-table-fix-point-outside-fixes-all ()
  "Point outside any table rewrites every table in the buffer."
  (should (equal (markdown-table-fix-tests--fix
                  "text\n\n| a | b |\n|-|-|\n\n| c  | d |\n|-|-|\n")
                 (concat "text\n\n"
                         "| a   | b   |\n| --- | --- |\n\n"
                         "| c   | d   |\n| --- | --- |\n"))))

(ert-deftest markdown-table-fix-idempotent ()
  "A canonical table is recognized and left untouched."
  (let ((once (markdown-table-fix-tests--fix
               "| a | bb |\n|:-|-:|\n| ccc | d |\n")))
    (should (equal once (markdown-table-fix-tests--fix once)))))

(ert-deftest markdown-table-fix-no-table-errors ()
  "A buffer without tables signals `user-error', not silence."
  (should-error (markdown-table-fix-tests--fix "plain text\n")
                :type 'user-error))

(provide 'markdown-table-fix-ert)
;;; markdown-table-fix-ert.el ends here
