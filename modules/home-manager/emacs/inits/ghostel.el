;; SPDX-License-Identifier: MIT
;; init ghostel

;; use-package's compile-time load runs inside `eval-when-compile', so the
;; byte compiler flags every ghostel function as possibly missing at runtime;
;; declare the ones referenced outside autoload/:commands declarations.
(declare-function ghostel-send-C-g "ghostel")

(use-package ghostel

  :init
  ;; Both startup.el (at daemon startup, headless) and server.el (per
  ;; parameterless client frame) consult initial-buffer-choice.  Only the
  ;; latter should spawn a terminal: at daemon startup the selected frame
  ;; is the daemon's dumb initial frame, so the terminal would size its
  ;; child programs to it (~80x25) instead of the real client frame.
  ;; Client frames — GUI or tty — carry the 'client frame parameter.
  (setq initial-buffer-choice
        (lambda ()
          (if (and (daemonp) (null (frame-parameter nil 'client)))
              (get-scratch-buffer-create)
            (ghostel))))
  (setq ghostel-module-auto-install nil)
  ;; libghostty counts scrollback in terminal page-memory bytes, not plain-text
  ;; bytes. The default 5 MB often retains only ~1–2k lines on a wide window
  ;; (e.g. `ls /nix/store` keeps a small tail, not megabytes of names).
  (setq ghostel-max-scrollback (* 64 1024 1024))

  (use-package ghostel-funcs

    :autoload
    (ch/ghostel--inject-buffer-name-env
     ch/ghostel-called
     ch/ghostel-send-buffer-env
     ch/ghostel-send-C-x
     ch/ghostel-toggle-escape-routing)

    :init
    (add-hook 'ghostel-pre-spawn-hook #'ch/ghostel--inject-buffer-name-env))

  (use-package evil-ghostel
    :after (ghostel evil)
    :hook (ghostel-mode . evil-ghostel-mode)
    :custom
    (evil-ghostel-escape 'evil "route ESC to Evil; C-c ESC toggles terminal")
    :config
    (define-key ghostel-mode-map (kbd "C-c <escape>") #'ch/ghostel-toggle-escape-routing))

  :commands
  (ghostel
   ghostel-clear-scrollback
   ch/ghostel-send-escape)

  :custom
  (ghostel-eval-cmds '(("find-file" find-file)
                       ("message" message)
                       ("ghostel-clear-scrollback" ghostel-clear-scrollback)))
  ;; Don't freeze the terminal into copy mode on a mouse click/drag.
  ;; The default (`copy') means an inadvertent drag silently drops the
  ;; live buffer into read-only copy mode: up/down then move point in
  ;; the frozen snapshot instead of reaching the shell, and in Evil
  ;; normal state the letter-key fast-exit doesn't fire (k/j/h/l are
  ;; motions, not self-insert), so it reads as "up/down locked out".
  ;; `nil' keeps the click in semi-char; the only cost is that a drag
  ;; selection can be clobbered by the next redraw and `M-w' isn't
  ;; bound for it — an acceptable trade to never get stuck.
  (ghostel-mouse-drag-input-mode nil "no copy-mode freeze on mouse drag")

  :config
  ;; C-g is Emacs's quit key, so keep it out of the terminal and put an
  ;; explicit sender on the C-c prefix alongside upstream's C-c C-c and
  ;; C-c C-d.  C-c C-x covers the key upstream reserves for Emacs with no
  ;; sender of its own (nano's exit key).
  ;;
  ;; Listing "C-g" leaves it unbound in `ghostel-mode-map' rather than
  ;; sending BEL, so Emacs's own `keyboard-quit' runs.  Upstream honored
  ;; the exception list for C-g in 0.40; before that it was hardwired and
  ;; this needed a `keymap-unset' after the fact.  Set through customize:
  ;; the option's `:set' rebuilds the keymaps, and the C-g binding is
  ;; computed there, so a plain `add-to-list' would not take effect.
  (customize-set-variable 'ghostel-keymap-exceptions
                          (cons "C-g" ghostel-keymap-exceptions))
  (keymap-set ghostel-mode-map "C-c C-g" #'ghostel-send-C-g)
  (keymap-set ghostel-mode-map "C-c C-x" #'ch/ghostel-send-C-x)
  (add-hook 'ghostel-mode-hook
            (lambda () (pixel-scroll-precision-mode -1))))
