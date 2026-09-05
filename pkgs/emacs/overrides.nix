# SPDX-License-Identifier: MIT
# Small emacsPackages overrides layered on top of emacs-overlay.
{
  lib,
  pkgs,
  # Sources of the packages consumed as plain (non-flake) inputs, keyed by
  # package name; each has a package.nix under this directory.
  sources,
  ...
}:
self: super: {
  pr-review = self.callPackage ./pr-review/package.nix { src = sources.pr-review; };

  # The local recipe is a floor, not a ceiling: it exists so package sets that
  # predate ghostel still get one.  Take the package set's own ghostel whenever
  # it has one and it is at least as new as the local recipe, so upstream fixes
  # arrive with an overlay bump instead of waiting on a manual re-pin.  Matching
  # an exact version here turns the floor into a freeze: the local recipe stops
  # being a fallback and becomes the only branch ever taken.
  ghostel =
    let
      pinnedGhostel = self.callPackage ./ghostel/package.nix { };
      superVersion = super.ghostel.version or null;
      atLeastPinned =
        superVersion != null && builtins.compareVersions superVersion pinnedGhostel.version >= 0;
    in
    if atLeastPinned then super.ghostel else pinnedGhostel;

  shell-maker = super.shell-maker.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      sed -i "/(require 'org-faces)/a (declare-function org-format-latex \"org\" t)" markdown-overlays.el
    '';
  });
}
