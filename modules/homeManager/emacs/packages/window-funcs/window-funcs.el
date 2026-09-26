;;; window-funcs --- Helper functions for window management -*- lexical-binding: t -*-
;; SPDX-License-Identifier: MIT
;;; Commentary:
;;; Code:

;;;###autoload
(defun alternate-buffer ()
  "Toggle to the last-seen buffer."
  (interactive)
  (switch-to-buffer (other-buffer)))

;;;###autoload
(defun alternate-window ()
  "Switch back and forth between current and last window in the current frame."
  (interactive)
  (let (;; switch to first window previously shown in this frame
        (prev-window (get-mru-window nil t t)))
    ;; Check window was not found successfully
    (unless prev-window (user-error "Last window not found"))
    (select-window prev-window)))

;;;###autoload
(defun switch-to-minibuffer-window ()
  "Switch to minibuffer window (if active)."
  (interactive)
  (when (active-minibuffer-window)
    (select-window (active-minibuffer-window))))

(defun window-funcs--find-window (all-frames)
  "Select a window chosen by the name of the buffer it displays.
Consider windows on all frames when ALL-FRAMES is non-nil, and give
the chosen window's frame input focus.  The current window sorts
last so plain RET never re-selects it."
  (let* ((windows (window-list-1 nil 0 (and all-frames t)))
         (windows (append (remq (selected-window) windows)
                          (and (memq (selected-window) windows)
                               (list (selected-window)))))
         (seen (make-hash-table :test #'equal))
         (candidates
          (mapcar
           (lambda (win)
             (let* ((base (concat
                           (when all-frames
                             (format "%s › " (frame-parameter
                                              (window-frame win) 'name)))
                           (buffer-name (window-buffer win))))
                    (n (gethash base seen 0))
                    (name (if (zerop n) base (format "%s <%d>" base n))))
               (puthash base (1+ n) seen)
               (cons name win)))
           windows))
         ;; identity sorters keep the window order above; the default
         ;; sorters would alphabetize and bury the MRU-ish ordering.
         (table (lambda (string pred action)
                  (if (eq action 'metadata)
                      '(metadata (category . window)
                                 (display-sort-function . identity)
                                 (cycle-sort-function . identity))
                    (complete-with-action action candidates string pred))))
         (win (cdr (assoc (completing-read "Window: " table nil t)
                          candidates))))
    (unless (window-live-p win)
      (user-error "Window no longer live"))
    (when all-frames
      (select-frame-set-input-focus (window-frame win)))
    (select-window win)))

;;;###autoload
(defun find-window ()
  "Select a window in the current frame by its displayed buffer's name."
  (interactive)
  (window-funcs--find-window nil))

;;;###autoload
(defun find-window-anywhere ()
  "Select a window on any frame by its displayed buffer's name.
Also gives the chosen window's frame input focus."
  (interactive)
  (window-funcs--find-window t))

(provide 'window-funcs)
;;; window-funcs.el ends here
