;;; render-dwim.el --- Render the diagram or image reference at point -*- lexical-binding: t -*-
;; SPDX-License-Identifier: MIT
;;; Commentary:
;; One command, `render-dwim', that turns whatever is at point into an
;; image in another window.  In order: the active region is rendered
;; as diagram source; an image or diagram file path at point is
;; opened; a fenced code block around point is rendered by the handler
;; for its info string; bare diagram source (a terminal's rendering of
;; a code block, where the fence markers may not survive) is
;; recognized by asking the mermaid toolchain and rendered.
;;
;; Rendered SVGs are content-addressed (hash of the source) under
;; `render-dwim-cache-directory', the same files the
;; claude-mermaid-display-hook writes while a Claude Code reply
;; streams, so either path produces the other's file and a re-render
;; after the cache is pruned lands on the identical name.
;;
;; Terminal buffers: ghostel marks the newlines it inserts at the
;; terminal width with the `ghostel-wrap' text property; source taken
;; from a buffer keeps its properties until `render-dwim--clean'
;; unwraps them, so long diagram lines survive soft wrapping.
;;; Code:

(require 'thingatpt)

(declare-function ghostel--filter-soft-wraps "ghostel")

(defgroup render-dwim nil
  "Render the diagram or image reference at point."
  :group 'tools)

(defcustom render-dwim-mermaid-command '("merman-cli" "mmdc")
  "Command list prefix for an mmdc-compatible mermaid renderer.
Input, output, and rendering flags are appended."
  :type '(repeat string)
  :group 'render-dwim)

(defcustom render-dwim-detect-command '("merman-cli" "detect")
  "Command list that reads diagram source on stdin and exits 0 only
when it recognizes a mermaid diagram type."
  :type '(repeat string)
  :group 'render-dwim)

(defcustom render-dwim-handlers
  '(("mermaid" . render-dwim--render-mermaid)
    ("plantuml" . render-dwim--render-plantuml)
    ("dot" . render-dwim--render-dot)
    ("graphviz" . render-dwim--render-dot))
  "Fence info string to handler.
A handler takes the block source (a string) and returns the file name
of the rendered image."
  :type '(alist :key-type string :value-type function)
  :group 'render-dwim)

(defcustom render-dwim-cache-directory
  (expand-file-name "render-dwim"
                    (or (getenv "XDG_CACHE_HOME") "~/.cache"))
  "Directory holding content-addressed rendered SVGs.
Shared with the claude-mermaid-display-hook; keep the two in step."
  :type 'directory
  :group 'render-dwim)

(defcustom render-dwim-file-extensions
  '("svg" "png" "jpg" "jpeg" "gif" "webp" "pdf" "mmd")
  "Extensions `render-dwim' opens (or, for .mmd, renders) from a path
at point."
  :type '(repeat string)
  :group 'render-dwim)

(defun render-dwim--cache-dir ()
  "The cache directory, created on first use."
  (unless (file-directory-p render-dwim-cache-directory)
    (make-directory render-dwim-cache-directory t))
  render-dwim-cache-directory)

(defun render-dwim--cache-file (source)
  "Content-addressed SVG file name for SOURCE.
The name is the first 12 hex digits of the sha256 of the source,
matching the shell side (sha256sum | cut -c1-12) in
claude-mermaid-display-hook.sh."
  (expand-file-name (concat (substring (secure-hash 'sha256 source) 0 12)
                            ".svg")
                    (render-dwim--cache-dir)))

(defun render-dwim--config-file ()
  "Path of the htmlLabels-off mermaid config, written on first use.
librsvg (Emacs's SVG renderer) silently drops <foreignObject>;
htmlLabels false makes mermaid emit native <text> labels instead
(both keys needed: top-level covers edge labels, flowchart covers
node labels)."
  (let ((file (expand-file-name "htmlLabels-off.json"
                                (render-dwim--cache-dir))))
    (unless (file-exists-p file)
      (with-temp-file file
        (insert "{\"htmlLabels\": false, "
                "\"flowchart\": {\"htmlLabels\": false}}")))
    file))

(defun render-dwim--run (command source)
  "Run COMMAND with SOURCE on stdin; return (EXIT-STATUS . OUTPUT)."
  (unless (executable-find (car command))
    (user-error "render-dwim: %s not found on PATH" (car command)))
  (with-temp-buffer
    (let ((status (apply #'call-process-region source nil (car command)
                         nil t nil (cdr command))))
      (cons status (string-trim (buffer-string))))))

(defun render-dwim--clean (text)
  "TEXT without terminal soft-wrap newlines or text properties, ending
in exactly one newline (the hash-parity normalization)."
  (let* ((unwrapped (if (fboundp 'ghostel--filter-soft-wraps)
                        (ghostel--filter-soft-wraps text)
                      text))
         (plain (substring-no-properties unwrapped)))
    (concat (string-trim-right plain "\n+") "\n")))

(defun render-dwim--render-mermaid (source)
  "Render mermaid SOURCE into the cache; return the SVG file name."
  (let ((out (render-dwim--cache-file source)))
    (unless (file-exists-p out)
      (let ((result (render-dwim--run
                     (append render-dwim-mermaid-command
                             (list "-i" "-" "-o" out "-q"
                                   "-c" (render-dwim--config-file)))
                     source)))
        (unless (and (eql (car result) 0) (file-exists-p out))
          (when (file-exists-p out) (delete-file out))
          (user-error "render-dwim: mermaid render failed: %s"
                      (cdr result)))))
    out))

(defun render-dwim--render-dot (source)
  "Render graphviz SOURCE into the cache; return the SVG file name."
  (let ((out (render-dwim--cache-file source)))
    (unless (file-exists-p out)
      (let ((result (render-dwim--run (list "dot" "-Tsvg" "-o" out)
                                      source)))
        (unless (and (eql (car result) 0) (file-exists-p out))
          (when (file-exists-p out) (delete-file out))
          (user-error "render-dwim: dot render failed: %s"
                      (cdr result)))))
    out))

(defun render-dwim--render-plantuml (source)
  "Render plantuml SOURCE into the cache; return the SVG file name."
  (let ((out (render-dwim--cache-file source)))
    (unless (file-exists-p out)
      (unless (executable-find "plantuml")
        (user-error "render-dwim: plantuml not found on PATH"))
      (with-temp-buffer
        (let ((status (call-process-region source nil "plantuml"
                                           nil (list t nil) nil
                                           "-tsvg" "-pipe")))
          (unless (and (eql status 0) (> (buffer-size) 0))
            (user-error "render-dwim: plantuml render failed (%s)"
                        status))
          (let ((coding-system-for-write 'binary))
            (write-region nil nil out nil 'silent)))))
    out))

(defun render-dwim--render-detected (source)
  "Render SOURCE as mermaid when the detector recognizes it."
  (let ((probe (render-dwim--run render-dwim-detect-command source)))
    (unless (eql (car probe) 0)
      (user-error "render-dwim: not recognized as diagram source: %s"
                  (cdr probe)))
    (render-dwim--render-mermaid source)))

(defun render-dwim--render-fence (fence)
  "Render FENCE, a (LANG . SOURCE) pair from `render-dwim--fence-at-point'.
A known info string uses its handler; an empty or unknown one falls
back to detection."
  (let* ((lang (car fence))
         (source (render-dwim--clean (cdr fence)))
         (handler (cdr (assoc lang render-dwim-handlers))))
    (if handler
        (funcall handler source)
      (render-dwim--render-detected source))))

(defun render-dwim--file-at-point ()
  "An existing image or diagram file referenced at point, or nil.
A trailing :LINE[:COL] suffix (the ghostel link shape) is dropped."
  (when-let* ((raw (thing-at-point 'filename t))
              (path (replace-regexp-in-string
                     ":[0-9]+\\(?::[0-9]+\\)?\\'" "" raw))
              (ext (file-name-extension path)))
    (when (member (downcase ext) render-dwim-file-extensions)
      (let ((expanded (expand-file-name path)))
        (when (file-exists-p expanded)
          expanded)))))

(defun render-dwim--fence-at-point ()
  "The fenced code block around point as (LANG . SOURCE), or nil.
Scans from the top of the buffer pairing fence lines, so a closing
fence above point is not mistaken for an opener.  SOURCE keeps its
text properties for `render-dwim--clean'."
  (save-excursion
    (let ((origin (line-beginning-position))
          (case-fold-search nil)
          open-start lang body-start)
      (goto-char (point-min))
      (catch 'hit
        (while (re-search-forward
                "^[ \t]*```\\([A-Za-z0-9_+-]*\\)[ \t]*$" nil t)
          (if (not open-start)
              (setq open-start (match-beginning 0)
                    lang (match-string-no-properties 1)
                    body-start (line-beginning-position 2))
            (when (and (<= open-start origin)
                       (<= origin (line-end-position)))
              (throw 'hit
                     (cons lang
                           (buffer-substring body-start
                                             (match-beginning 0)))))
            (setq open-start nil lang nil body-start nil)))
        nil))))

(defun render-dwim--block-around-point ()
  "The blank-line-delimited block around point, common indent
stripped, or nil on a blank line.  Keeps text properties for
`render-dwim--clean'."
  (unless (save-excursion (beginning-of-line) (looking-at-p "[ \t]*$"))
    (let* ((beg (save-excursion
                  (if (re-search-backward "^[ \t]*$" nil t)
                      (line-beginning-position 2)
                    (point-min))))
           (end (save-excursion
                  (if (re-search-forward "^[ \t]*$" nil t)
                      (line-beginning-position)
                    (point-max))))
           (text (buffer-substring beg end))
           (lines (split-string (substring-no-properties text) "\n"))
           (indent (let ((widths (delq nil
                                       (mapcar
                                        (lambda (line)
                                          (unless (string-match-p
                                                   "\\`[ \t]*\\'" line)
                                            (and (string-match "\\`[ ]*"
                                                               line)
                                                 (match-end 0))))
                                        lines))))
                     (if widths (apply #'min widths) 0))))
      (if (zerop indent)
          text
        ;; Strip on the propertized string so soft-wrap marks survive
        ;; for `render-dwim--clean'.
        (mapconcat (lambda (line)
                     (if (<= (length line) indent)
                         line
                       (substring line indent)))
                   (split-string text "\n")
                   "\n")))))

(defun render-dwim--display (file)
  "Show FILE in another window; .mmd files render first.  Returns t."
  (if (string-suffix-p ".mmd" file t)
      (render-dwim--display
       (render-dwim--render-mermaid
        (render-dwim--clean
         (with-temp-buffer
           (insert-file-contents file)
           (buffer-string)))))
    (find-file-other-window file))
  t)

;;;###autoload
(defun render-dwim ()
  "Render what is at point and show it in another window.
The active region, an image or diagram file path, a fenced code
block, or a block of bare diagram source, in that order."
  (interactive)
  (cond
   ((use-region-p)
    (render-dwim--display
     (render-dwim--render-detected
      (render-dwim--clean
       (buffer-substring (region-beginning) (region-end))))))
   ((when-let* ((file (render-dwim--file-at-point)))
      (render-dwim--display file)))
   ((when-let* ((fence (render-dwim--fence-at-point)))
      (render-dwim--display (render-dwim--render-fence fence))))
   ((when-let* ((block (render-dwim--block-around-point)))
      (render-dwim--display
       (render-dwim--render-detected (render-dwim--clean block)))))
   (t (user-error "render-dwim: nothing renderable at point"))))

(provide 'render-dwim)
;;; render-dwim.el ends here
