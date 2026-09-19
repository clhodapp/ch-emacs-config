;; SPDX-License-Identifier: MIT
;; init mode-line

(defun ch-emacs-config--coding-tag ()
  "Describe this buffer's encoding, or return \"\" when it is unremarkable.

Stock Emacs renders `mode-line-mule-info' unconditionally as a coding
mnemonic plus a line-ending mnemonic, which on a UTF-8 LF buffer is the
two characters \"U:\".  Every buffer is that, so the segment is a
constant, and the one time it varies it says \"(DOS)\" rather than
anything a reader parses at a glance.  This shows nothing in the normal
case and spells the deviation out in the rare one."
  (let* ((coding buffer-file-coding-system)
         (base (and coding (coding-system-base coding)))
         (eol (and coding (coding-system-eol-type coding)))
         ;; undecided resolves its own base to the detected coding, and
         ;; prefer-utf-8 is what Emacs picks for many decoded files, so
         ;; both count as plain UTF-8 here.  Unibyte buffers are the
         ;; internal process ones (network streams and the like), where an
         ;; encoding readout means nothing.
         (plain-coding (memq base '(utf-8 prefer-utf-8 undecided))))
    (if (or (null coding)
            (not enable-multibyte-characters)
            (and plain-coding (eq eol 0)))
        ""
      (let ((parts (delq nil
                         (list (unless plain-coding (symbol-name base))
                               ;; eol is 0/1/2 for LF/CRLF/CR, or a vector
                               ;; when the style is unspecified; only the
                               ;; two non-LF integers are worth naming.
                               (pcase eol
                                 (1 "CRLF")
                                 (2 "CR")
                                 (_ nil))))))
        (concat " " (mapconcat #'identity parts " "))))))

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
  (mode-line-collapse-minor-modes '(not envrc-mode jinx-mode))

  ;; Keep the input-method indicator, which is blank unless an input
  ;; method is active and is worth seeing when one is, and replace the
  ;; always-on encoding mnemonics with `ch-emacs-config--coding-tag'.
  ;; The help-echo and mouse-1 binding match what the stock end-of-line
  ;; descriptor offered, so selecting the tag still cycles the style.
  (mode-line-mule-info
   '(""
     (current-input-method
      (:propertize ("" current-input-method-title)
                   help-echo (concat "Current input method: " current-input-method)
                   mouse-face mode-line-highlight))
     (:propertize (:eval (ch-emacs-config--coding-tag))
                  help-echo "Buffer encoding differs from UTF-8 with Unix line endings\nmouse-1: Cycle end-of-line style"
                  mouse-face mode-line-highlight
                  local-map (keymap (mode-line keymap (mouse-1 . mode-line-change-eol)))))))
