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

  shell-maker = super.shell-maker.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      sed -i "/(require 'org-faces)/a (declare-function org-format-latex \"org\" t)" markdown-overlays.el
    '';
  });
}
