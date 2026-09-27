;; SPDX-License-Identifier: MIT
;; init mode-line
;;
;; The normal buffer shows no status icons at all.  Normal means: saved,
;; writable, local, in an ordinary window, UTF-8 with Unix line endings.
;; That describes nearly every buffer nearly all the time, so stock
;; Emacs spends the left edge of every mode line restating it in
;; punctuation ("U:---"), and the reader has to decode a placeholder to
;; learn that nothing is unusual.  Each indicator below renders the
;; empty string in the normal case and a nerd-icons glyph otherwise, so
;; anything visible on the left edge is something that deviates.

(declare-function nerd-icons-mdicon "nerd-icons")

(defun ch-emacs-config--mode-line-icon (name)
  "Return the nerd-icons glyph NAME, or \"\" if nerd-icons is unavailable.
The nerd-icons bundle loads the library on demand rather than at
startup, so the mode line asks for a glyph without forcing the load and
falls back to nothing rather than erroring during redisplay."
  (if (require 'nerd-icons nil t)
      (nerd-icons-mdicon name)
    ""))

(defun ch-emacs-config--buffer-status-icon ()
  "Show a glyph when this buffer is read-only or has unsaved changes.

Read-only wins when both hold: a buffer that cannot be saved is the more
pressing fact about it.  Buffers with no file behind them (the scratch
buffer, process output, dired) are never reported as unsaved, since
their modified flag tracks nothing a save would clear."
  (cond
   (buffer-read-only
    (propertize (concat " " (ch-emacs-config--mode-line-icon "nf-md-lock"))
                'help-echo "Buffer is read-only\nmouse-1: Make writable"
                'mouse-face 'mode-line-highlight
                'local-map (let ((map (make-sparse-keymap)))
                             (define-key map [mode-line mouse-1]
                                         #'mode-line-toggle-read-only)
                             map)))
   ((and (buffer-modified-p) buffer-file-name)
    (propertize (concat " " (ch-emacs-config--mode-line-icon "nf-md-content_save_edit"))
                'help-echo "Buffer has unsaved changes\nmouse-1: Save"
                'mouse-face 'mode-line-highlight
                'local-map (let ((map (make-sparse-keymap)))
                             (define-key map [mode-line mouse-1] #'save-buffer)
                             map)))
   (t "")))

(defun ch-emacs-config--remote-icon ()
  "Show a glyph when this buffer's directory is on a remote machine."
  (if (and default-directory (file-remote-p default-directory))
      (propertize (concat " " (ch-emacs-config--mode-line-icon "nf-md-server_network"))
                  'help-echo (concat "Remote: " (abbreviate-file-name default-directory))
                  'mouse-face 'mode-line-highlight)
    ""))

(defun ch-emacs-config--dedicated-icon ()
  "Show a glyph when this window refuses to display other buffers."
  (if (window-dedicated-p)
      (propertize (concat " " (ch-emacs-config--mode-line-icon "nf-md-pin"))
                  'help-echo "Window is dedicated to this buffer"
                  'mouse-face 'mode-line-highlight)
    ""))

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
                  local-map (keymap (mode-line keymap (mouse-1 . mode-line-change-eol))))))

  ;; The left edge, rebuilt.  Dropped: `mode-line-front-space' and
  ;; `mode-line-frame-identification', which exist to pad terminal
  ;; frames differently from graphical ones and are a space and two
  ;; spaces in every graphical frame; the "   " literal that followed
  ;; the buffer name; and the two-character `mode-line-modified' pair,
  ;; whose four states were spelled "--", "**", "%%" and "%*".  The
  ;; read-only, unsaved, remote and dedicated facts they carried are now
  ;; icons that appear only when true.  `%b' replaces the padded `%12b',
  ;; so a short buffer name no longer trails blanks to a 12-column stop.
  ;;
  ;; `mode-line-client' goes too, for the same reason but one specific
  ;; to this configuration: it renders "@" on any frame with a `client'
  ;; parameter, and the daemon bundle runs Emacs as a daemon that every
  ;; frame connects to through emacsclient.  The only frame without the
  ;; parameter is the daemon's own initial terminal frame, which has no
  ;; window system and is never looked at, so "@" marks every frame the
  ;; user ever sees.  A window where it were absent would be the
  ;; surprise, and that window does not occur here.
  (mode-line-format
   '("%e"
     mode-line-mule-info
     (:eval (ch-emacs-config--buffer-status-icon))
     (:eval (ch-emacs-config--remote-icon))
     (:eval (ch-emacs-config--dedicated-icon))
     " "
     (:propertize "%b"
                  face mode-line-buffer-id
                  help-echo "Buffer name\nmouse-1: Previous buffer\nmouse-3: Next buffer"
                  mouse-face mode-line-highlight
                  local-map (keymap (mode-line keymap
                                               (mouse-1 . mode-line-previous-buffer)
                                               (mouse-3 . mode-line-next-buffer))))
     "  "
     mode-line-position
     evil-mode-line-tag
     (project-mode-line project-mode-line-format)
     (vc-mode vc-mode)
     "  "
     mode-line-modes
     mode-line-misc-info
     mode-line-end-spaces)))
