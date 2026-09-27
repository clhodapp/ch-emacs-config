;; SPDX-License-Identifier: MIT
;; init indent-bars
(use-package indent-bars
  :hook ((python-ts-mode yaml-ts-mode ruby-ts-mode java-ts-mode nix-ts-mode)
         . indent-bars-mode)
  :custom
  (indent-bars-treesit-support t)
  (indent-bars-treesit-wrap '((python argument_list parameters
                                      list list_comprehension
                                      dictionary dictionary_comprehension
                                      parenthesized_expression subscript)))
  (indent-bars-treesit-ignore-blank-lines-types '("module")))
