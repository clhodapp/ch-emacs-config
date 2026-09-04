;; SPDX-License-Identifier: MIT
;; init evil
(autoload 'ffap-file-at-point "ffap")

(defvar evil-motion-state-map)

(defun ch/compile-dwim ()
  "Compile from the project root when inside a project, else from here.
Modes with a native render/preview shadow `<leader> c' in their own map
(mermaid, plantuml, elisp); this is the fallback for everything else."
  (interactive)
  (if (project-current)
      (call-interactively #'project-compile)
    (call-interactively #'compile)))

(defun ch/find-file-at-point ()
  "Find file, seeding the minibuffer from the filename at point via ffap."
  (interactive)
  ;; Seed via DIR + basename INITIAL, never an absolute INITIAL: that
  ;; would land after `default-directory' as a shadowed "dir//abs" pair,
  ;; and `vertico-directory-tidy' only strips the dead prefix on typed
  ;; input (`self-insert-command'), not on programmatic insertion.
  (let ((filename (when-let* ((f (ffap-file-at-point))) (expand-file-name f))))
    (find-file
     (if filename
         (read-file-name "Find file: " (file-name-directory filename) filename
                         nil (file-name-nondirectory filename))
       ;; DEFAULT-FILENAME = `default-directory', as `find-file-read-args'
       ;; does: RET on the untouched directory input counts as null input
       ;; and returns the default — without this it falls back to
       ;; `buffer-file-name' and reopens the current file instead of dired.
       (read-file-name "Find file: " nil default-directory)))))

(defun ch/delete-window-and-buffer ()
  "Delete the selected window, and kill its buffer unless shown elsewhere.
The window goes first: on a sole window `delete-window' signals and the
buffer survives untouched.  The buffer is kept when any other window on
any frame still displays it."
  (interactive)
  (let ((buffer (current-buffer)))
    (delete-window)
    (unless (get-buffer-window buffer t)
      (kill-buffer buffer))))

(defun ch/scratch (key)
  "Switch to the scratch buffer named for KEY, creating it if absent.
KEY is read as one key, so `<leader> s a' lands in \"scratch-a\"."
  (interactive "cScratch buffer: ")
  (switch-to-buffer (get-buffer-create (format "scratch-%c" key))))

(defun ch/leader-prefix-title (keys title)
  "Title the motion-state `<leader>' prefix at KEYS as TITLE in key guides.
Wraps the keymap already bound at KEYS when one exists, so titles and
prefix bindings may arrive in any order across init bundles."
  (let ((key (kbd (concat "<leader> " keys))))
    (evil-global-set-key
     'motion key
     (cons title
           (let ((def (lookup-key evil-motion-state-map key)))
             (if (keymapp def) def (make-sparse-keymap)))))))

(use-package evil

  :demand t

  :init
  (customize-set-variable 'evil-want-keybinding nil)
  (customize-set-variable 'evil-overriding-maps nil)
  (customize-set-variable 'evil-intercept-maps nil)
  ;; In visual-line buffers j/k/0/$/V follow visual lines and the g
  ;; prefix inverts to the logical-line motions.  Load-order matters:
  ;; evil installs the swapped bindings at load time.
  (customize-set-variable 'evil-respect-visual-line-mode t)

  ;; init evil-collection
  (use-package evil-collection

    :demand t

    :commands
    evil-collection-init

    :after evil

    :custom
    (evil-collection-key-blacklist '("SPC") "space key is <leader>")

    :config
    (evil-collection-init))

  ;; init evil-commentary (the gc comment operator)
  (use-package evil-commentary

    :demand t

    :commands
    evil-commentary-mode

    :after evil

    :config
    (evil-commentary-mode 1))

  :commands
  (evil-mode
   ch/ghostel-toggle-escape-routing
   evil-quit-all
   evil-window-down
   evil-window-left
   evil-window-move-far-left
   evil-window-move-far-right
   evil-window-move-very-bottom
   evil-window-move-very-top
   evil-window-right
   evil-window-up
   evil-write-all)

  :autoload
  (evil-set-leader
   evil-global-set-key)

  :custom
  (evil-shift-width 2 "set default indent to two spaces")
  (evil-undo-system 'undo-redo "use the native undo-redo system from emacs")

  :config
  (evil-mode 1)

  (evil-set-leader 'motion (kbd "SPC"))
  (ch/leader-prefix-title "b" "buffers")
  (ch/leader-prefix-title "f" "files")
  (ch/leader-prefix-title "F" "frames")
  (ch/leader-prefix-title "h" "help")
  (ch/leader-prefix-title "h d" "describe")
  (ch/leader-prefix-title "q" "quit")
  (ch/leader-prefix-title "t" "toggles")
  (ch/leader-prefix-title "v" "ghostel")
  (ch/leader-prefix-title "w" "windows")
  (evil-global-set-key 'motion (kbd "<leader> SPC") #'execute-extended-command)
  (evil-global-set-key 'motion (kbd "<leader> c") #'ch/compile-dwim)
  ;; Elisp's "compile": make the buffer take effect.
  (evil-define-key 'motion emacs-lisp-mode-map (kbd "<leader> c") #'eval-buffer)
  (evil-global-set-key 'motion (kbd "<leader> TAB") #'alternate-buffer)
  ;; Literal content search across all open buffers.
  (evil-global-set-key 'motion (kbd "<leader> b /") #'consult-line-multi)
  ;; D = d plus the window; the buffer dies even if shown elsewhere.
  (evil-global-set-key 'motion (kbd "<leader> b D") #'kill-buffer-and-window)
  (evil-global-set-key 'motion (kbd "<leader> b b") #'consult-buffer)
  (evil-global-set-key 'motion (kbd "<leader> b d") #'kill-current-buffer)
  ;; Retrieval by description (embedding-ranked; b / is the literal layer).
  (evil-global-set-key 'motion (kbd "<leader> b f") #'find-buffer-by-description)
  (evil-global-set-key 'motion (kbd "<leader> b m") #'buffer-menu)
  (evil-global-set-key 'motion (kbd "<leader> b n") #'next-buffer)
  (evil-global-set-key 'motion (kbd "<leader> b p") #'previous-buffer)
  (evil-global-set-key 'motion (kbd "<leader> b r") #'revert-buffer)
  (evil-global-set-key 'motion (kbd "<leader> b w") #'read-only-mode)
  (evil-global-set-key 'motion (kbd "<leader> f S") #'evil-write-all)
  (evil-global-set-key 'motion (kbd "<leader> f c") #'copy-file)
  (evil-global-set-key 'motion (kbd "<leader> f f") #'ch/find-file-at-point)
  (evil-global-set-key 'motion (kbd "<leader> f F") #'find-file)
  (evil-global-set-key 'motion (kbd "<leader> f r") #'consult-recent-file)
  (evil-global-set-key 'motion (kbd "<leader> f s") #'save-buffer)
  ;; ? = find by description, the semantic sibling of the / literal layer.
  (evil-global-set-key 'motion (kbd "<leader> F ?") #'find-frame-by-description)
  (evil-global-set-key 'motion (kbd "<leader> F D") #'delete-other-frames)
  (evil-global-set-key 'motion (kbd "<leader> F F") #'other-frame)
  (evil-global-set-key 'motion (kbd "<leader> F d") #'delete-frame)
  (evil-global-set-key 'motion (kbd "<leader> F f") #'select-frame-by-name)
  (evil-global-set-key 'motion (kbd "<leader> F n") #'make-frame)
  ;; Named frames are what makes F f a real finder.
  (evil-global-set-key 'motion (kbd "<leader> F r") #'set-frame-name)
  (evil-global-set-key 'motion (kbd "<leader> h d b") #'describe-bindings)
  (evil-global-set-key 'motion (kbd "<leader> h d c") #'describe-char)
  (evil-global-set-key 'motion (kbd "<leader> h d f") #'describe-function)
  (evil-global-set-key 'motion (kbd "<leader> h d k") #'describe-key)
  (evil-global-set-key 'motion (kbd "<leader> h d m") #'describe-mode)
  (evil-global-set-key 'motion (kbd "<leader> h d t") #'describe-theme)
  (evil-global-set-key 'motion (kbd "<leader> h d v") #'describe-variable)
  (evil-global-set-key 'motion (kbd "<leader> m") #'consult-man)
  (evil-global-set-key 'motion (kbd "<leader> q q") #'evil-quit-all)
  (evil-global-set-key 'motion (kbd "<leader> s") #'ch/scratch)
  (evil-global-set-key 'motion (kbd "<leader> t c") #'display-fill-column-indicator-mode)
  (evil-global-set-key 'motion (kbd "<leader> t f") #'follow-mode)
  (evil-global-set-key 'motion (kbd "<leader> t h") #'hl-line-mode)
  (evil-global-set-key 'motion (kbd "<leader> t l") #'display-line-numbers-mode)
  (evil-global-set-key 'motion (kbd "<leader> t t") #'toggle-truncate-lines)
  (evil-global-set-key 'motion (kbd "<leader> t v") #'visual-line-mode)
  (evil-global-set-key 'motion (kbd "<leader> t w") #'whitespace-mode)
  (evil-global-set-key 'motion (kbd "<leader> v c") #'ch/ghostel-called)
  (evil-global-set-key 'motion (kbd "<leader> v e") #'ch/ghostel-toggle-escape-routing)
  (evil-global-set-key 'motion (kbd "<leader> v ESC") #'ch/ghostel-send-escape)
  (evil-global-set-key 'motion (kbd "<leader> v v") #'ghostel)
  (evil-global-set-key 'motion (kbd "<leader> w -") #'split-window-below)
  (evil-global-set-key 'motion (kbd "<leader> w /") #'split-window-right)
  (evil-global-set-key 'motion (kbd "<leader> w =") #'balance-windows)
  ;; D = d plus the buffer, unless another window still shows it.
  (evil-global-set-key 'motion (kbd "<leader> w D") #'ch/delete-window-and-buffer)
  (evil-global-set-key 'motion (kbd "<leader> w F") #'find-window-anywhere)
  (evil-global-set-key 'motion (kbd "<leader> w H") #'evil-window-move-far-left)
  (evil-global-set-key 'motion (kbd "<leader> w J") #'evil-window-move-very-bottom)
  (evil-global-set-key 'motion (kbd "<leader> w K") #'evil-window-move-very-top)
  (evil-global-set-key 'motion (kbd "<leader> w L") #'evil-window-move-far-right)
  ;; ? = find by description, the semantic sibling of the / literal layer.
  (evil-global-set-key 'motion (kbd "<leader> w ?") #'find-window-by-description)
  (evil-global-set-key 'motion (kbd "<leader> w TAB") #'alternate-window)
  (evil-global-set-key 'motion (kbd "<leader> w b") #'switch-to-minibuffer-window)
  (evil-global-set-key 'motion (kbd "<leader> w d") #'delete-window)
  (evil-global-set-key 'motion (kbd "<leader> w f") #'find-window)
  (evil-global-set-key 'motion (kbd "<leader> w h") #'evil-window-left)
  (evil-global-set-key 'motion (kbd "<leader> w j") #'evil-window-down)
  (evil-global-set-key 'motion (kbd "<leader> w k") #'evil-window-up)
  (evil-global-set-key 'motion (kbd "<leader> w l") #'evil-window-right)
  ;; "only", as in vim's C-w o.
  (evil-global-set-key 'motion (kbd "<leader> w o") #'delete-other-windows)
  (evil-global-set-key 'motion (kbd "<leader> w s") #'split-window-below)
  (evil-global-set-key 'motion (kbd "<leader> w w") #'other-window))
