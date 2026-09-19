;; SPDX-License-Identifier: MIT
;; init mode-line

(use-package emacs
  :demand t
  :custom
  ;; Most minor-mode lighters report a mode that is globally on in every
  ;; buffer (which-key, eldoc, evil-commentary, the consult-gh
  ;; integrations), so they say the same thing everywhere and say
  ;; nothing about the buffer being looked at.  Collapse them behind the
  ;; single indicator in `mode-line-collapse-minor-modes-to', which
  ;; expands on demand.
  ;;
  ;; The exceptions carry per-buffer state that changes:
  ;; envrc-mode's lighter tracks the direnv status of this buffer's
  ;; directory, and jinx-mode's names the spell-check language.
  (mode-line-collapse-minor-modes '(not envrc-mode jinx-mode)))
