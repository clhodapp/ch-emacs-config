# SPDX-License-Identifier: MIT
{
  lib,
  pkgs,
  emacsPackage,
  bundles,
  sources,
  emacsOverlayRev ? null,
}:
let
  manifest = import ../../modules/homeManager/emacs/lib/package-manifest.nix {
    inherit
      lib
      pkgs
      emacsPackage
      bundles
      sources
      emacsOverlayRev
      ;
  };
in
pkgs.writeText "emacs-package-manifest.json" (builtins.toJSON manifest)
