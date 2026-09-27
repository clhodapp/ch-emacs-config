;;; mermaid-preview.el --- Render mermaid buffer previews -*- lexical-binding: t -*-
;; SPDX-License-Identifier: MIT
;;; Commentary:
;; Renders the current buffer's mermaid source to SVG with an
;; mmdc-compatible headless renderer (merman-cli by default) and
;; displays the result in an image buffer.
;;; Code:

(defgroup mermaid-preview nil
  "Render mermaid buffers to image previews."
  :group 'tools)

(defcustom mermaid-preview-command '("merman-cli" "mmdc")
  "Command list prefix for an mmdc-compatible mermaid renderer.
Input and output arguments are appended."
  :type '(repeat string)
  :group 'mermaid-preview)

(defcustom mermaid-preview-buffer-name "*mermaid-preview*"
  "Name of the buffer displaying rendered previews."
  :type 'string
  :group 'mermaid-preview)

(defun mermaid-preview--display (svg-data source-name)
  "Show SVG-DATA in the preview buffer, labeled with SOURCE-NAME."
  (with-current-buffer (get-buffer-create mermaid-preview-buffer-name)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert-image (create-image svg-data 'svg t))
      (insert "\n" source-name "\n"))
    (special-mode)
    (display-buffer (current-buffer))))

;;;###autoload
(defun mermaid-preview ()
  "Render the current buffer as mermaid and display the result."
  (interactive)
  (let* ((source-name (buffer-name))
         (src (buffer-substring-no-properties (point-min) (point-max)))
         (out (make-temp-file "mermaid-preview-" nil ".svg"))
         (stderr-buffer (generate-new-buffer " *mermaid-preview stderr*"))
         (proc (make-process
                :name "mermaid-preview"
                :command (append mermaid-preview-command (list "-i" "-" "-o" out))
                :connection-type 'pipe
                :noquery t
                :stderr stderr-buffer
                :sentinel
                (lambda (process _event)
                  (when (memq (process-status process) '(exit signal))
                    (unwind-protect
                        (if (eql (process-exit-status process) 0)
                            (mermaid-preview--display
                             (with-temp-buffer
                               (set-buffer-multibyte nil)
                               (insert-file-contents-literally out)
                               (buffer-string))
                             source-name)
                          (message "mermaid-preview failed: %s"
                                   (with-current-buffer stderr-buffer
                                     (string-trim (buffer-string)))))
                      (delete-file out)
                      (kill-buffer stderr-buffer)))))))
    (process-send-string proc src)
    (process-send-eof proc)))

(provide 'mermaid-preview)
;;; mermaid-preview.el ends here
