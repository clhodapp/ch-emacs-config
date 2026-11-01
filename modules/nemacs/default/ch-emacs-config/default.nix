# SPDX-License-Identifier: MIT
{ closure-inputs, closure-lib, ... }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ch-emacs-config;
  # The pieces the configuration is built from come from the published
  # library.
  emacsLib = closure-lib.ch-emacs-config;

  # The programs the init spawns (git, ripgrep, the language servers,
  # ...) and the init lines pinning each to a store path; the option
  # below exposes the table so a consumer can substitute a package or
  # leave a program to PATH.
  executablesLib = emacsLib.mkExecutablesLib {
    inherit lib pkgs;
    languageServerTable = emacsLib.languageServers;
  };
  executablesTable = executablesLib.table // {
    # Taken from the flake input rather than `pkgs`: this module is
    # evaluated against the consumer's package set, which need not carry
    # the merman-nix overlay.
    merman = executablesLib.table.merman // {
      default = closure-inputs.merman-nix.packages.${pkgs.stdenv.hostPlatform.system}.merman-preview;
      defaultText = "the merman-preview package of this flake's `merman-nix` input";
    };
  };

  # The fonts the init names. Unlike the programs above, a font cannot be
  # pinned into the init by store path: Emacs resolves a font by family
  # through fontconfig, so the package has to be in the profile for the
  # name to resolve. The Home Manager module installs whatever this
  # names, which is why the init carries no font family of its own.
  fontsLib = emacsLib.mkFontsLib { inherit lib pkgs; };

  packageEntry =
    entry:
    lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      inherit (entry) default description;
      defaultText = lib.literalExpression entry.defaultText;
    };
in
{
  options.ch-emacs-config = {
    executables = lib.mkOption {
      type = lib.types.submodule {
        options = lib.mapAttrs (_name: packageEntry) executablesTable;
      };
      default = { };
      description = ''
        The programs the init spawns, pinned into it as store paths so
        the editor runs the same on a host that has none of them (the
        language servers are pinned the same way, from the shared server
        table). Set one to null to leave that program to PATH at run
        time; the README lists what a host must then provide.
      '';
    };

    fonts = lib.mkOption {
      type = lib.types.submodule {
        options = lib.mapAttrs (_name: packageEntry) fontsLib.table;
      };
      default = { };
      description = ''
        The fonts the init names. The Home Manager module installs each
        one into the profile, and the init names its family, so the
        editor renders the same on a host that has none of them
        installed. Set one to null to leave that font to the host, in
        which case the init stops naming its family too and Emacs falls
        back to its own default.
      '';
    };

    fontHeight = lib.mkOption {
      type = lib.types.ints.positive;
      default = 120;
      description = ''
        The `:height` of the default face, in tenths of a point. Fonts
        differ in how much of the em they fill, so a size that suits one
        family may want adjusting for another.
      '';
    };
  };

  config = {
    package = lib.mkDefault (
      pkgs.ch-emacs-config.emacs or (throw ''
        The ch-emacs-config nemacs module has no default `package` because
        `pkgs` lacks `pkgs.ch-emacs-config.emacs`: apply this flake's
        `overlays.default` (a caisson consumer: list the flake in
        `projects`) to the package set nemacs evaluates on, or set
        `package` to an Emacs explicitly.
      '')
    );

    overrides = [
      (emacsLib.emacsPackageOverrides {
        inherit lib pkgs;
        # Packages consumed as plain (non-flake) inputs.
        sources = {
          inherit (closure-inputs) pr-review ghostel;
        };
      })
      emacsLib.emacsPackages
    ];

    earlyInit = emacsLib.earlyInitEl;

    bundles = import ./bundles.nix {
      inherit lib;
      inherit (emacsLib) initFiles;
    };

    # The forms every bundle's init is compiled after: use-package for
    # the `use-package` forms, and evil's keybinding switch, which has
    # to be off before evil loads for evil-collection to take over.
    # Priority 100 puts them ahead of the `emacs` bundle (order 200).
    packages = epkgs: [ epkgs.use-package ];
    init = lib.mkMerge [
      (lib.mkOrder 100 ''
        (eval-when-compile (require 'use-package))
        (eval-when-compile (customize-set-variable 'evil-want-keybinding nil))
      '')
      (lib.mkAfter (
        executablesLib.initContent {
          inherit (config) bundles;
          inherit (cfg) executables;
        }
      ))
      (lib.mkAfter (
        fontsLib.initContent {
          inherit (cfg) fonts;
          defaultHeight = cfg.fontHeight;
        }
      ))
    ];
  };
}
