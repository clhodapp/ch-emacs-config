# SPDX-License-Identifier: MIT
{ closure-lib, ... }:
{
  inputs,
  lib,
  ...
}:
{

  imports = [ inputs.flake-parts.flakeModules.partitions ];

  debug = false;
  # The Emacs base packages and the ELPA/MELPA pins are this flake's
  # package overlay registry entries (pkg-overlays/, registered on mkLib):
  # every package set applies `default`, which imports `emacs-packages`,
  # and the flake exports both, as `pkgOverlays` for a caisson consumer's
  # `projects` and as plain `overlays` for any other. merman-nix's
  # `default` entry arrives through `projects` and is applied, not
  # exported.

  caisson.libOverlays.exported = libOverlays: { inherit (libOverlays) default; };

  caisson.modules = {
    flake.exported = modules: { inherit (modules) default; };
    homeManager.exported = modules: { inherit (modules) emacs; };
    nemacs.exported = modules: { inherit (modules) default; };
  };

  # The editors of the nemacs module `default`, on each Emacs base
  # package, and the package manifest of the first. The flake-parts
  # integration checks that each package builds, as
  # `<package>-package`.
  perSystem =
    { pkgs, ... }:
    let
      # The configuration on one Emacs base package. The exported
      # packages close over every program the init spawns.
      mkEmacsDefault =
        emacsPackage:
        closure-lib.nemacs.evalNemacs {
          inherit pkgs;
          modules = [
            lib.caisson.modules.nemacs.default
            {
              key = "ch-emacs-config.checks.package";
              package = emacsPackage;
            }
          ];
        };
      emacsConfiguration = mkEmacsDefault pkgs.ch-emacs-config.emacs;
      emacsPgtkConfiguration = mkEmacsDefault pkgs.ch-emacs-config.emacs-pgtk;
      emacsOverlayRev = inputs.emacs-overlay.rev or inputs.emacs-overlay.sourceInfo.rev or null;
    in
    {
      packages = {
        emacs = emacsConfiguration.config.build.package;
        emacs-pgtk = emacsPgtkConfiguration.config.build.package;
        # The package manifest of the exported Emacs, written out as
        # JSON: what is installed and at which version.
        emacs-package-manifest = pkgs.writeText "emacs-package-manifest.json" (
          builtins.toJSON (
            closure-lib.ch-emacs-config.mkPackageManifest {
              inherit pkgs emacsOverlayRev;
              lib = pkgs.lib;
              inherit (emacsConfiguration) config;
            }
          )
        );
      };
    };

  # The checks of ch-emacs-config, with the pins of tests/dependencies
  # that only the checks need (configs/flake/checks). The caisson top
  # gathers the checks of every configuration declared inside it into
  # its `checks` output. This selector passes the configuration up to
  # nothing, so a flake that reads the exports of ch-emacs-config
  # evaluates neither the configuration nor its pins.
  caisson.flake-parts.configurations.checks = lib.caisson.flake-parts.mkConfiguration {
    inherit (lib.caisson.pins.flake-compat ../../../tests/dependencies) dependencies;
  };
  caisson.flake-parts.exported = _: { };

  partitionedAttrs.formatter = "formatter";

  partitions.formatter = {
    extraInputs = (lib.caisson.pins.flake-compat ../../../tests/dependencies).dependencies;
    module =
      { inputs, ... }:
      {
        imports = [ inputs.treefmt-nix.flakeModule ];
        # treefmt reads the perSystem `pkgs`, which caisson's nixpkgs
        # module supplies from the `default` package config declared on
        # mkLib (configs/nixpkgsConfig/default).
        perSystem.treefmt.programs.nixfmt.enable = true;
      };
  };

}
