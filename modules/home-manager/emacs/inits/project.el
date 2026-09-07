;; SPDX-License-Identifier: MIT
;; init project.el
(declare-function ghostel-exec "ghostel")
(defvar consult-ripgrep-args)

(defun ch/project--ripgrep-program ()
  "The program `consult-ripgrep' would run, or nil if it is not there.
That is the first word of `consult-ripgrep-args', which the pinned
init points at a store path; a bare \"rg\" is looked up on
`exec-path'."
  (require 'consult)
  (let ((program (if (stringp consult-ripgrep-args)
                     (car (split-string consult-ripgrep-args))
                   (car consult-ripgrep-args))))
    (and (stringp program) (executable-find program))))

(defun ch/project-grep ()
  "Grep the current project, with ripgrep when available."
  (interactive)
  (if (ch/project--ripgrep-program)
      (consult-ripgrep)
    (consult-grep)))

(defun ch/display-buffer-full-frame (buffer)
  "Show BUFFER alone in the selected frame and select its window."
  (let ((window (display-buffer buffer
                                '((display-buffer-same-window
                                   display-buffer-use-some-window)))))
    (when window
      (select-window window)
      (delete-other-windows window))))

(defun ch/project-buffer ()
  "Switch to a project buffer, using consult-project-buffer if available."
  (interactive)
  (if (fboundp 'consult-project-buffer) (consult-project-buffer) (call-interactively #'project-switch-to-buffer)))

(use-package project
  :demand t
  :custom
  (project-switch-commands
   '((project-claude "Claude" ?a)
     (project-eshell "Eshell" ?e)
     (project-find-dir "Find directory" ?d)
     (project-find-file "Find file" ?f)
     (project-ghostel "Ghostel" ?v)
     (ch/project-grep "Grep" ?g)
     (project-vc-dir "Magit/VC" ?m)))
  :config
  (defun project-ghostel ()
    "Launch ghostel in the current project root, with a project-named buffer."
    (interactive)
    (let* ((proj (project-current t))
           (dir (project-root proj))
           (default-directory dir)
           (ghostel-buffer-name (concat "*ghostel:" (project-name proj) "*")))
      (ghostel)))
  (defun project-claude ()
    "Run an interactive Claude Code session in the current project root.

The session lives in a ghostel terminal named for the project and
fills the frame; a second call while that session is still running
just revisits it."
    (interactive)
    (require 'ghostel)
    (let* ((proj (project-current t))
           (name (concat "*claude:" (project-name proj) "*"))
           (existing (get-buffer name)))
      (if (and existing (process-live-p (get-buffer-process existing)))
          (ch/display-buffer-full-frame existing)
        (let ((buffer (get-buffer-create name)))
          (with-current-buffer buffer
            (setq default-directory (project-root proj)))
          ;; Display first: ghostel-exec sizes the new terminal to the
          ;; window showing the buffer (80x24 otherwise).
          (ch/display-buffer-full-frame buffer)
          (ghostel-exec buffer (if (boundp 'claude-queue-program)
                                   claude-queue-program
                                 "claude"))))))
  (ch/leader-prefix-title "p" "project")
  (evil-global-set-key 'motion (kbd "<leader> p p") #'project-switch-project)
  (evil-global-set-key 'motion (kbd "<leader> p f") #'project-find-file)
  (evil-global-set-key 'motion (kbd "<leader> p b") #'ch/project-buffer)
  (evil-global-set-key 'motion (kbd "<leader> p g") #'ch/project-grep)
  (evil-global-set-key 'motion (kbd "<leader> p k") #'project-kill-buffers)
  (evil-global-set-key 'motion (kbd "<leader> p d") #'project-dired))
