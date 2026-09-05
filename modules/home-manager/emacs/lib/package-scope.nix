# SPDX-License-Identifier: MIT
{
  lib,
  pkgs,
  emacsPackage,
  bundles,
  sources,
  extraInitContent ? "",
  # The same two extension points the module offers, so a layer built on
  # this configuration can run its own checks against an Emacs carrying
  # both layers rather than reimplementing this.
  extraOverrides ? [ ],
  localPackageOverlays ? [ ],
}:
let
  version = emacsPackage.version or "0";
  emacsOverrides = lib.foldl' lib.composeExtensions (import ../../../../pkgs/emacs/overrides.nix {
    inherit lib pkgs sources;
  }) extraOverrides;
  epkgs = (pkgs.emacsPackagesFor emacsPackage).overrideScope emacsOverrides;
  bundleLib = import ./bundles.nix { inherit lib; };
  local = lib.fix (
    final:
    lib.foldl' (prev: overlay: prev // overlay final prev) (import ../packages/scope.nix {
      inherit epkgs version;
    }) localPackageOverlays
  );
  packages = import ../packages {
    inherit
      epkgs
      pkgs
      version
      extraInitContent
      ;
    epkgsToplevel = epkgs;
    bundleInitContent = bundleLib.initContent bundles;
    bundlePackages = bundleLib.packages bundles epkgs local;
  };
  wrapEmacs = import ./wrap-emacs.nix { inherit lib pkgs; };
in
packages
// {
  emacs = wrapEmacs (emacsPackage.pkgs.withPackages (_epkgs: [ packages.default ]));
}
