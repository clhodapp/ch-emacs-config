# SPDX-License-Identifier: MIT
#
# The default package overlay: `pkgs.ch-emacs-config.emacs`,
# `.emacs-pgtk` and `.emacs-nox`, the Emacs base packages the
# configuration is validated against (packages/emacs-base.nix picks the
# newest supported major nixpkgs carries as a final release). It imports
# the ELPA/MELPA pins, so a package set that applies it builds Emacs
# packages from the set the configuration is checked against.
#
# A consumer that lists this flake in `projects` holds it as
# `ch-emacs-config/default`, which its package sets apply by default.
# The scope name is bound here, so the packages land under
# `pkgs.ch-emacs-config` in any consumer.
{ closure-lib, ... }:
{
  imports = [ closure-lib.caisson-core.libManifest.pkgOverlays.emacs-packages ];
  overlay = closure-lib.caisson.nixpkgs.mkPackagesOverlay ./packages "ch-emacs-config";
}
