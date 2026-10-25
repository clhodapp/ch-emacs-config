;;; consult-ghostel-ert.el --- Tests for the consult-ghostel wiring -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: MIT

;;; Commentary:
;;
;; Runs against the fully loaded init (load-init.el first).  The init
;; loads consult-ghostel only once both ghostel and consult are loaded,
;; and the init-load check loads neither, so it cannot see whether the
;; mode comes on or where the leader keys land.  These tests load both
;; the way a first terminal and a first `consult-buffer' would, then
;; check what `consult-ghostel-mode' registers and what the leader keys
;; resolve to.

;;; Code:

(require 'ert)
(require 'ghostel)
(require 'consult)

(ert-deftest ch-consult-ghostel-mode-on-after-both-load ()
  "Loading ghostel and consult loads consult-ghostel and turns the mode on."
  (should (featurep 'consult-ghostel))
  (should (bound-and-true-p consult-ghostel-mode)))

(ert-deftest ch-consult-ghostel-sources-registered ()
  "The hidden Ghostel sources are in consult's buffer source lists."
  (should (memq 'consult-ghostel-source-hidden consult-buffer-sources))
  (should (memq 'consult-ghostel-project-source-hidden
                consult-project-buffer-sources)))

(ert-deftest ch-consult-ghostel-line-advice-installed ()
  "`consult-line' candidates go through the soft-wrap joining advice."
  (should (advice-member-p #'consult-ghostel--line-candidates
                           'consult--line-candidates))
  (should (advice-member-p #'consult-ghostel--line-point-placement
                           'consult--line-point-placement)))

(ert-deftest ch-consult-ghostel-leader-pickers-global ()
  "The buffer pickers sit on the global `<leader> v' prefix."
  (should (eq (lookup-key evil-motion-state-map (kbd "<leader> v b"))
              #'consult-ghostel))
  (should (eq (lookup-key evil-motion-state-map (kbd "<leader> v p"))
              #'consult-ghostel-project)))

(ert-deftest ch-consult-ghostel-leader-history-in-terminals ()
  "The shell history picker is bound in terminals only."
  (should (eq (lookup-key (evil-get-auxiliary-keymap ghostel-mode-map 'motion)
                          (kbd "<leader> v h"))
              #'consult-ghostel-history))
  (should-not (eq (lookup-key evil-motion-state-map (kbd "<leader> v h"))
                  #'consult-ghostel-history)))

;;; consult-ghostel-ert.el ends here
