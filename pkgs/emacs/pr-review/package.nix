# SPDX-License-Identifier: MIT
# pr-review, built from the `pr-review` flake input: a plain Emacs package
# repository (github:clhodapp/emacs-pr-review), not a flake. That repository
# is a fork of blahgeek/emacs-pr-review carrying non-blocking, staged PR
# loading. The version carries the pinned commit's date; the pin advances
# with the other external inputs.
#
# The upstream MELPA recipe is `:files (:defaults "graphql")`, because the
# package reads its queries from a graphql/ directory beside the elisp at
# runtime (see `pr-review--get-graphql'), so that directory has to be
# installed alongside the compiled files.
{
  lib,
  melpaBuild,
  src,
  ghub,
  magit,
  markdown-mode,
}:
let
  date = src.lastModifiedDate;
  isoDate = "${lib.substring 0 4 date}-${lib.substring 4 2 date}-${lib.substring 6 2 date}";
in
melpaBuild {
  pname = "pr-review";
  version = "0.1.0-unstable-${isoDate}";
  inherit src;

  files = ''(:defaults "graphql")'';

  packageRequires = [
    ghub
    magit
    markdown-mode
  ];

  meta = {
    homepage = "https://github.com/clhodapp/emacs-pr-review";
    description = "Review GitHub pull requests from Emacs, loaded asynchronously";
    license = lib.licenses.gpl3Plus;
  };
}
