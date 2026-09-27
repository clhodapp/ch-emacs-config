# SPDX-License-Identifier: MIT
# The `pkgs.ch-emacs-config.*` scope: the Emacs base packages this
# configuration is validated against, one per toolkit variant.
{ callPackage, ... }:
{
  emacs = callPackage ./emacs/package.nix { };
  emacs-pgtk = callPackage ./emacs-pgtk/package.nix { };
  emacs-nox = callPackage ./emacs-nox/package.nix { };
}
