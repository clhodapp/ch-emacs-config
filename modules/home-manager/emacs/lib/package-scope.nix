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
  # Programs the init spawns, pinned into it as store paths: an attrset
  # over the names in lib/executables.nix, each a package or null (leave
  # that program to PATH). Unnamed entries take the table's defaults;
  # merman has none, so an Emacs built without it resolves the mermaid
  # tooling from PATH.
  executables ? { },
}:
let
  version = emacsPackage.version or "0";
  executablesLib = import ./executables.nix { inherit lib pkgs; };
  pinnedInitContent = executablesLib.initContent {
    inherit bundles;
    executables = lib.mapAttrs (_: entry: entry.default) executablesLib.table // executables;
  };
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
      ;
    # The pins come last, after whatever the caller appended, as they do
    # in the module.
    extraInitContent = extraInitContent + "\n" + pinnedInitContent;
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
