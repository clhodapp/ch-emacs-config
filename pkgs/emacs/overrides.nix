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

  # ghostel ships its evil integration under extensions/, which its own
  # recipe does not install (melpa's :defaults takes top-level .el only).
  # Build it from the same source as the core, so the two cannot drift:
  # this file advises ghostel internals, and a version skew between them
  # is what the vendored copy this replaces existed to paper over.
  evil-ghostel = self.callPackage ./evil-ghostel/package.nix {
    src = self.ghostel.src;
    inherit (self.ghostel) version;
  };

  shell-maker = super.shell-maker.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      sed -i "/(require 'org-faces)/a (declare-function org-format-latex \"org\" t)" markdown-overlays.el
    '';
  });
}
