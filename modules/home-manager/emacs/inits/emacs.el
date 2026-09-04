;; SPDX-License-Identifier: MIT
;; init emacs (this runs first)

(defun ch-emacs-config--truncate-lines ()
  "Stop wrapping long lines in the current buffer."
  (setq truncate-lines t))

(use-package emacs
  :demand t
  :custom
  (major-mode-remap-alist '((python-mode . python-ts-mode)
                            (java-mode . java-ts-mode)
                            (ruby-mode . ruby-ts-mode)
                            (js-mode . js-ts-mode)
                            (js-json-mode . json-ts-mode)
                            (sh-mode . bash-ts-mode)
                            (conf-toml-mode . toml-ts-mode)
                            (yaml-mode . yaml-ts-mode)))

  (auto-save-file-name-transforms `((".*" ,(concat (getenv "XDG_DATA_HOME") "/Emacs/autosaves") t)))
  (backup-directory-alist `(("." . ,(concat (getenv "XDG_DATA_HOME") "/Emacs/backups"))))
  (savehist-file (concat (getenv "XDG_DATA_HOME") "/Emacs/savehist"))
  (save-place-file (concat (getenv "XDG_DATA_HOME") "/Emacs/places"))
  (inhibit-startup-screen t)
  ;; Same-named files disambiguate by leading path segments
  ;; (fleet/default.nix vs machines/default.nix), so finder narrowing
  ;; can use directory words instead of opaque <2> suffixes.
  (uniquify-buffer-name-style 'forward)

  ;; Horizontal scrolling is set up GLOBALLY, in every buffer, not just
  ;; the text buffers that truncate by default (see the hooks in
  ;; :config).  Toggling truncation on anywhere -- <leader> t t, or a
  ;; mode that sets it -- should land in a window that already scrolls
  ;; sideways properly.
  ;;
  ;; truncate-partial-width-windows must be nil, or a window narrower
  ;; than its threshold (50 columns by default) wraps anyway, which is
  ;; exactly the vertical splits where truncation matters most.
  (truncate-partial-width-windows nil)
  ;; Scroll only the line point is on, so the rest of the buffer stays
  ;; put while editing off the right edge.
  (auto-hscroll-mode 'current-line)
  ;; Ride the edge a column at a time rather than jumping by a fraction
  ;; of the window width, keeping two columns of context ahead of point.
  (hscroll-step 1)
  (hscroll-margin 2)
  ;; Trackpad and tilt-wheel horizontal gestures scroll the window.  If
  ;; they come out reversed on some pointer, set
  ;; mouse-wheel-flip-direction rather than changing this.
  (mouse-wheel-tilt-scroll t)

  :custom-face
  (default ((t (:font "Hack Nerd Font" :height 120))))

  :config
  ;; Truncate in text buffers only: prose files whose line breaks are
  ;; the author's, so a long line is a real line worth scrolling to.
  ;; Everything else keeps whatever it already does.  Source code
  ;; (prog-mode) is deliberately not included, and neither is rendered
  ;; output like help and Info, where the line breaks are the
  ;; renderer's and scrolling sideways to read a sentence is a
  ;; nuisance.  Man-mode is the exception that needs no help: it
  ;; truncates on its own, because man pages arrive pre-formatted to a
  ;; fixed width and wrapping them would double-break every line.
  ;;
  ;; markdown-ts-mode derives from fundamental-mode rather than
  ;; text-mode, so it needs its own hook (the jinx spell-check list
  ;; carries the same exception for the same reason).
  ;;
  ;; Per-buffer escape hatch: <leader> t v (visual-line-mode) is the
  ;; one to reach for, since it word-wraps AND, via
  ;; evil-respect-visual-line-mode, makes j/k follow screen lines.
  ;; <leader> t t (toggle-truncate-lines) unwraps at character
  ;; boundaries and leaves j jumping whole paragraphs.
  (dolist (hook '(text-mode-hook markdown-ts-mode-hook))
    (add-hook hook #'ch-emacs-config--truncate-lines))

  (recentf-mode 1)
  ;; Persist minibuffer histories so vertico's history-based ranking
  ;; survives restarts.
  (savehist-mode 1)
  ;; Reopen files at the last point position (400-file LRU).
  (save-place-mode 1)
  (set-fontset-font t 'emoji "Symbola")
  (set-fontset-font t 'emoji (font-spec :family "Noto Color Emoji") nil 'prepend)
  ;; Saved Customize may reference removed themes (e.g. sanityinc-tomorrow-eighties)
  ;; or invalid faces (e.g. shadow in ansi-color-faces-vector). Reassert ours.
  (setq custom-enabled-themes nil)
  (when (boundp 'ansi-color-faces-vector)
    (setq ansi-color-faces-vector
          [default default default default default default default default])))

(use-package outline
  :demand t)

(defun ch-emacs-config--load-theme (frame)
  "Load the theme once on the first graphical frame, then remove itself."
  (when (display-graphic-p frame)
    (with-selected-frame frame
      (load-theme 'sanityinc-tomorrow-night t))
    (remove-hook 'after-make-frame-functions #'ch-emacs-config--load-theme)))

(use-package color-theme-sanityinc-tomorrow
  :ensure nil
  :demand t
  :after outline
  :config
  ;; In daemon mode defer until the first graphical frame is created; in
  ;; interactive mode there is already a frame so load immediately.
  (if (daemonp)
      (add-hook 'after-make-frame-functions #'ch-emacs-config--load-theme)
    (load-theme 'sanityinc-tomorrow-night t)))
