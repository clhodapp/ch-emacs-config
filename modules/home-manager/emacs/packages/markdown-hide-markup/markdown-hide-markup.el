;;; markdown-hide-markup --- Hide markdown formatting characters while editing -*- lexical-binding: t -*-
;; SPDX-License-Identifier: MIT
;;; Commentary:
;;
;; A buffer-local minor mode that hides Markdown's formatting
;; characters in `markdown-ts-mode': the `#' of a heading, the `*' and
;; `_' around emphasis, the backticks of a code span, a link's brackets
;; and destination, and the rest of the delimiters `markdown-ts-mode'
;; knows how to mark.
;;
;; The hiding itself is upstream's.  `markdown-ts-mode' puts an
;; `invisible' text property with the symbol `markdown-ts--markup' on
;; every delimiter it fontifies whenever the buffer-local variable
;; `markdown-ts-hide-markup' is non-nil, and its
;; `markdown-ts-toggle-hide-markup' command flips that variable and
;; adds or removes the symbol from the buffer's invisibility spec.
;; What upstream does not provide is a minor mode: nothing to put on a
;; mode hook, nothing `describe-mode' lists, no lighter, and no single
;; form that turns it on for every Markdown buffer.  This package is
;; that mode.
;;
;; It adds one behavior beyond the toggle.  Hidden markup is awkward to
;; edit through, because point lands inside text that is not displayed
;; and the characters that deleting and moving act on are not the ones
;; on screen.  So the construct point is inside is revealed: with
;; `markdown-hide-markup-reveal' at its default `construct', the
;; delimiters of the innermost inline or block construct containing
;; point are displayed while point is in it, and hide again once point
;; leaves.  Set it to nil to hide unconditionally, or to `line' to
;; reveal everything on point's line.
;;
;; Revealing narrows the invisibility spec rather than refontifying.
;; The region to reveal gets a distinct invisible symbol,
;; `markdown-hide-markup-shown', which is deliberately not in the
;; buffer's invisibility spec, in place of upstream's; the property is
;; swapped back when point moves away.  Refontification restores
;; upstream's symbol on any text it redraws, and the post-command
;; update re-reveals from there, so the two do not fight.
;;
;;; Code:

(require 'treesit)

(declare-function markdown-ts--set-hide-markup "markdown-ts-mode" (value))
(defvar markdown-ts-hide-markup)

(defgroup markdown-hide-markup nil
  "Hide Markdown formatting characters in `markdown-ts-mode'."
  :prefix "markdown-hide-markup-"
  :group 'text)

(defcustom markdown-hide-markup-reveal 'construct
  "Which markup to reveal around point.
`construct' reveals the delimiters of the innermost Markdown
construct containing point, `line' reveals all markup on point's
line, and nil keeps markup hidden wherever point is."
  :type '(choice (const :tag "The construct point is in" construct)
                 (const :tag "Point's whole line" line)
                 (const :tag "Nothing" nil)))

(defcustom markdown-hide-markup-lighter " MD-hide"
  "Mode-line lighter for `markdown-hide-markup-mode'.
Set to nil for no lighter."
  :type '(choice string (const :tag "None" nil)))

(defconst markdown-hide-markup--shown 'markdown-hide-markup-shown
  "Invisibility symbol standing in for upstream's on revealed markup.
It is absent from the buffer's invisibility spec, so text carrying
it is displayed.")

(defconst markdown-hide-markup--hidden 'markdown-ts--markup
  "The invisibility symbol `markdown-ts-mode' puts on hidden markup.")

(defvar-local markdown-hide-markup--revealed nil
  "Bounds (START . END) of the region currently revealed, or nil.")

;; `define-minor-mode' defines this at the bottom of the file, but
;; `markdown-hide-markup--update' above it reads the variable; without
;; the forward declaration the byte compiler calls that a reference to a
;; free variable, which this package's build treats as an error.
(defvar markdown-hide-markup-mode)

(defun markdown-hide-markup--swap (start end from to)
  "Replace invisible property FROM with TO between START and END.
Only the runs actually carrying FROM are touched, so text made
invisible for another reason (an outline fold, say) is left alone."
  (with-silent-modifications
    (save-restriction
      (widen)
      (let ((pos (max start (point-min)))
            (limit (min end (point-max))))
        (while (< pos limit)
          (let ((next (next-single-property-change pos 'invisible nil limit)))
            (when (eq (get-text-property pos 'invisible) from)
              (put-text-property pos next 'invisible to))
            (setq pos next)))))))

(defun markdown-hide-markup--hide-region (start end)
  "Re-hide revealed markup between START and END."
  (markdown-hide-markup--swap start end
                              markdown-hide-markup--shown
                              markdown-hide-markup--hidden))

(defun markdown-hide-markup--show-region (start end)
  "Reveal hidden markup between START and END."
  (markdown-hide-markup--swap start end
                              markdown-hide-markup--hidden
                              markdown-hide-markup--shown))

(defconst markdown-hide-markup--block-types
  '("atx_heading" "setext_heading" "list_item" "fenced_code_block"
    "indented_code_block" "block_quote" "pipe_table" "thematic_break"
    "link_reference_definition" "paragraph")
  "Block-level node types taken as the construct point is in.")

(defconst markdown-hide-markup--inline-types
  '("emphasis" "strong_emphasis" "strikethrough" "code_span"
    "inline_link" "image" "shortcut_link" "full_reference_link"
    "collapsed_reference_link" "uri_autolink" "email_autolink")
  "Inline node types taken as the construct point is in.")

(defun markdown-hide-markup--node-of-types (pos language types)
  "Return the innermost node of one of TYPES at POS in LANGUAGE, or nil.
LANGUAGE is a language symbol rather than a parser object, because
`markdown-ts-mode' embeds `markdown-inline' as a local parser per
inline region: there is no one inline parser to hand to
`treesit-node-at', and the language form picks the right one."
  (when-let* ((node (ignore-errors (treesit-node-at pos language))))
    (treesit-parent-until
     node
     (lambda (candidate) (member (treesit-node-type candidate) types))
     t)))

(defun markdown-hide-markup--node-at (pos)
  "Return the innermost interesting Markdown node containing POS, or nil.
An inline construct wins over the block containing it, so point
inside emphasis reveals the emphasis markers rather than every
delimiter in the paragraph."
  (or (markdown-hide-markup--node-of-types
       pos 'markdown-inline markdown-hide-markup--inline-types)
      (markdown-hide-markup--node-of-types
       pos 'markdown markdown-hide-markup--block-types)))

(defun markdown-hide-markup--region-for-point ()
  "Return the (START . END) to reveal around point, or nil for none."
  (pcase markdown-hide-markup-reveal
    ('line (cons (pos-bol) (min (point-max) (1+ (pos-eol)))))
    ('construct
     (let ((node (or (markdown-hide-markup--node-at (point))
                     ;; At the end of a construct `treesit-node-at'
                     ;; already looks past it, so try the character
                     ;; before point as well.
                     (and (> (point) (point-min))
                          (markdown-hide-markup--node-at (1- (point)))))))
       (when node
         (cons (treesit-node-start node) (treesit-node-end node)))))
    (_ nil)))

(defun markdown-hide-markup--update ()
  "Reveal the markup around point and re-hide what point left."
  (when markdown-hide-markup-mode
    (let ((wanted (and markdown-hide-markup-reveal
                       (markdown-hide-markup--region-for-point))))
      (when markdown-hide-markup--revealed
        (markdown-hide-markup--hide-region (car markdown-hide-markup--revealed)
                                           (cdr markdown-hide-markup--revealed)))
      (when wanted
        (markdown-hide-markup--show-region (car wanted) (cdr wanted)))
      (setq markdown-hide-markup--revealed wanted))))

;;;###autoload
(define-minor-mode markdown-hide-markup-mode
  "Hide Markdown formatting characters in the current buffer.
A heading's leading hashes, emphasis markers, code-span backticks,
link brackets and destinations, and the other delimiters
`markdown-ts-mode' marks stop being displayed.  The buffer text is
unchanged: the characters are still there to move over, search for,
and save, they are only not shown.

The construct point is inside is revealed while point is in it, so
that editing acts on text that is on screen.  See
`markdown-hide-markup-reveal'."
  :lighter markdown-hide-markup-lighter
  :group 'markdown-hide-markup
  (unless (derived-mode-p 'markdown-ts-mode)
    (setq markdown-hide-markup-mode nil)
    (user-error "`markdown-hide-markup-mode' needs `markdown-ts-mode'"))
  (require 'markdown-ts-mode)
  (if markdown-hide-markup-mode
      (progn
        (setq-local markdown-ts-hide-markup t)
        (markdown-ts--set-hide-markup t)
        (add-hook 'post-command-hook #'markdown-hide-markup--update nil t)
        (let ((markdown-hide-markup-mode t))
          (markdown-hide-markup--update)))
    (remove-hook 'post-command-hook #'markdown-hide-markup--update t)
    (markdown-hide-markup--hide-region (point-min) (point-max))
    (setq markdown-hide-markup--revealed nil)
    (setq-local markdown-ts-hide-markup nil)
    (markdown-ts--set-hide-markup nil)))

;;;###autoload
(defun markdown-hide-markup-mode-maybe ()
  "Turn on `markdown-hide-markup-mode' in a `markdown-ts-mode' buffer.
Does nothing in any other mode, so it is safe on a hook that fires
more widely than Markdown."
  (when (derived-mode-p 'markdown-ts-mode)
    (markdown-hide-markup-mode 1)))

(provide 'markdown-hide-markup)
;;; markdown-hide-markup.el ends here
