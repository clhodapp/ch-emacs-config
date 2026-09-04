# SPDX-License-Identifier: MIT
{
  lib,
  pkgs,
  emacsPackage,
  bundles,
  sources,
  extraInitContent ? "",
}:
let
  version = emacsPackage.version or "0";
  emacsOverrides = import ../../../../pkgs/emacs/overrides.nix {
    inherit lib pkgs sources;
  };
  epkgs = (pkgs.emacsPackagesFor emacsPackage).overrideScope emacsOverrides;
  bundleLib = import ./bundles.nix { inherit lib; };
  local = import ../packages/scope.nix { inherit epkgs version; };
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
