# SPDX-License-Identifier: MIT
#
# The local ch-emacs-config library namespace: the values this
# configuration publishes, for the modules here and for a layer built on
# top of them. Every reader takes them from the composed library, so
# each value has one name and the directory layout of this repo stays
# internal.
#
# Everything the published values are built from lives in this
# directory: the executables and bundle helpers, the in-tree Emacs
# packages and their builder, the init files, the Emacs package-set
# overrides, and the early-init file. The Home Manager module reads the
# same pieces back through `lib.ch-emacs-config`, so nothing under
# `modules/` is read from outside the module and nothing here is read
# by path from another directory.
{ ... }:
{

  imports = [ ];

  overlay = _final: prev: {
    ch-emacs-config = (prev.ch-emacs-config or { }) // {
      # The Emacs package scope: an editor built from a bundle
      # selection, the init that configures it, and the programs the
      # init spawns pinned as store paths. A layer that adds bundles
      # calls this to build an Emacs carrying both layers.
      mkEmacsScope = import ./package-scope.nix;

      # The bundle definitions this configuration offers: what each
      # bundle turns on, the packages behind it, and the init it
      # contributes. A layer extends this attrset with bundles it
      # defines.
      bundleSpec = import ./bundle-spec.nix;

      # The language-server table: one description of how to spawn each
      # server, so every LSP client configured alongside this editor
      # agrees about how a server starts.
      languageServers = import ./language-servers.nix;

      # The pieces the scope above is assembled from, for the Home
      # Manager module, which builds the same editor inside a home, and
      # for the checks. Each takes the library and package set of its
      # caller, as the scope does.

      # `{ lib }` to the bundle helpers: the ordered init of a bundle
      # selection and the packages it needs.
      mkBundleLib = import ./bundles.nix;

      # `{ lib, pkgs, languageServerTable }` to the table of programs
      # the init spawns and the init lines pinning them.
      mkExecutablesLib = import ./executables.nix;

      # `{ epkgs, version }` to the in-tree package scope, with
      # `mkLocalBuild` for a layer that adds packages the same way.
      mkLocalPackageScope = import ./packages/scope.nix;

      # The in-tree packages and the `default` init package built from
      # a bundle selection; see packages/default.nix for the arguments.
      mkPackages = import ./packages;

      # `{ lib, pkgs }` to a function wrapping an Emacs so it starts
      # from this configuration's early-init.
      mkWrapEmacs = import ./wrap-emacs.nix;

      # `{ pkgs, sources, ... }` to the Emacs package-set overrides
      # layered over emacs-overlay: the packages consumed as plain
      # inputs and the carried upstream fixes.
      emacsPackageOverrides = import ./emacs-packages/overrides.nix;

      # `{ pkgs }` to the program that merges declared words into the
      # enchant personal dictionary at activation.
      mkJinxMergePersonalDict = import ./jinx-merge-personal-dict.nix;

      # The package manifest of an Emacs built from a bundle selection:
      # what is installed and at which version, as data.
      mkPackageManifest = import ./package-manifest.nix;

      # The early-init the module installs and the wrapper bakes in.
      earlyInitEl = builtins.readFile ./early-init.el;

      # The init files by file name, and the source directory of each
      # in-tree package, for checks that load them directly.
      initFiles = builtins.mapAttrs (name: _: ./inits + "/${name}") (builtins.readDir ./inits);
      packageSources = {
        ch-evil-ghostel = ./packages/ch-evil-ghostel;
        ghostel-funcs = ./packages/ghostel-funcs;
        markdown-table-fix = ./packages/markdown-table-fix;
        mermaid-preview = ./packages/mermaid-preview;
        render-dwim = ./packages/render-dwim;
        window-funcs = ./packages/window-funcs;
      };
    };
  };

}
