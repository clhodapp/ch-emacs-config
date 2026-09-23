;;; early-init.el --- ch-emacs-config host isolation -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Declarative Emacs from ch-emacs-config must not inherit mutable host
;; init (e.g. ~/.emacs custom-set-variables).  early-init runs before the
;; default user init file is loaded.

;;; Code:

(setq inhibit-default-init t)
(setq custom-file nil)
(setq custom-enabled-themes nil)

;; Flake-wrapped Emacs passes --init-directory to a read-only store path.
;; Relocate before init so packages (e.g. transient) can persist runtime data.
(when (string-prefix-p "/nix/store/" user-emacs-directory)
  (setq user-emacs-directory
        (if-let* ((xdg (getenv "XDG_CONFIG_HOME")))
            (expand-file-name "emacs/" xdg)
          (expand-file-name ".emacs.d/" (getenv "HOME")))))

;; Keep async JIT as a safety net for Lisp that missed AoT.
(when (featurep 'native-compile)
  (require 'comp-run)
  ;; Core Emacs also AoT-compiles a few files under share/emacs/native-lisp/,
  ;; but startup only prepends lib/emacs/VERSION/native-lisp/.  Add the share
  ;; tree before site-start so those artifacts are visible.
  (when (boundp 'data-directory)
    (let ((share-native-lisp (expand-file-name "../../native-lisp/" data-directory)))
      (when (file-directory-p share-native-lisp)
        (add-to-list 'native-comp-eln-load-path share-native-lisp))))
  ;; Suppress known false positives:
  ;; - *-loaddefs.el.gz: autoload stubs marked no-native-compile
  ;; - site-start.el, subdirs.el: Nix AoT bootstrap files that Emacs late-loads
  ;;   and would otherwise reprobe on every startup
  (setq native-comp-jit-compilation-deny-list
        (append '("loaddefs\\.el\\.gz$"
                  "site-start\\.el$"
                  "subdirs\\.el$")
                native-comp-jit-compilation-deny-list)))

;;; early-init.el ends here
