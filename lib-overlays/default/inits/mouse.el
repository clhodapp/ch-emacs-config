;; SPDX-License-Identifier: MIT
;; init mouse
(use-package mouse
  :demand t

  :config
  ;; Right-click opens a context menu built on demand from
  ;; `context-menu-functions' (undo, region ops, plus whatever the major
  ;; and minor modes contribute) instead of running
  ;; `mouse-save-then-kill'.  The mode takes `down-mouse-3' in its own
  ;; `context-menu-mode-map'.  Evil's state maps are consulted first
  ;; (`evil-mode-map-alist' lives in `emulation-mode-map-alists', which
  ;; outranks `minor-mode-map-alist') but leave `down-mouse-3' unbound,
  ;; so lookup falls through and no per-state binding is needed.
  (context-menu-mode 1))
