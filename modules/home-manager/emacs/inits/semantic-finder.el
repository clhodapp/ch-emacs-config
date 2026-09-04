;; SPDX-License-Identifier: MIT
;; init semantic-finder
(use-package semantic-finder
  :commands
  (find-buffer-by-description
   find-window-by-description
   find-frame-by-description)
  ;; Warm the embedding index in the background; on machines without the
  ;; embedding server the first failed request backs the indexer off.
  :hook
  (emacs-startup . semantic-finder-index-mode))
