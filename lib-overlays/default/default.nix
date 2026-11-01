# SPDX-License-Identifier: MIT
#
# The local ch-emacs-config library namespace: the values this
# configuration publishes, for the modules here and for a layer built on
# top of them. Every reader takes them from the composed library, so
# each value has one name and the directory layout of this repo stays
# internal.
#
# Everything the published values are built from lives in this
# directory: the executables table, the in-tree Emacs packages, the init
# files, the Emacs package-set overrides, and the early-init file. The
# nemacs and Home Manager modules read the same pieces back through
# `lib.ch-emacs-config`, so nothing under `modules/` is read from outside
# the module and nothing here is read by path from another directory.
{ ... }:
{

  imports = [ ];

  overlay = _final: prev: {
    ch-emacs-config = (prev.ch-emacs-config or { }) // {
      # The language-server table: one description of how to spawn each
      # server, so every LSP client configured alongside this editor
      # agrees about how a server starts.
      languageServers = import ./language-servers.nix;

      # `{ lib, pkgs, languageServerTable }` to the table of programs
      # the init spawns and the init lines pinning them.
      mkExecutablesLib = import ./executables.nix;

      # `{ lib, pkgs }` to the table of fonts the init names and the init
      # lines naming them.
      mkFontsLib = import ./fonts.nix;

      # The in-tree Emacs packages, as an overlay on a nemacs package
      # set (`final: prev:`), built with its `nemacsBuild`.
      emacsPackages = import ./packages;

      # `{ pkgs, sources, ... }` to the Emacs package-set overrides
      # layered over emacs-overlay: the packages consumed as plain
      # inputs and the carried upstream fixes.
      emacsPackageOverrides = import ./emacs-packages/overrides.nix;

      # `{ pkgs }` to the program that merges declared words into the
      # enchant personal dictionary at activation.
      mkJinxMergePersonalDict = import ./jinx-merge-personal-dict.nix;

      # The package manifest of a nemacs configuration built from this
      # one: what is installed and at which version, as data.
      mkPackageManifest = import ./package-manifest.nix;

      # The early-init of the configuration.
      earlyInitEl = builtins.readFile ./early-init.el;

      # The init files by file name, and the source directory of each
      # in-tree package, for the bundles and for checks that load them
      # directly.
      initFiles = builtins.mapAttrs (name: _: ./inits + "/${name}") (builtins.readDir ./inits);
      packageSources = {
        ch-evil-ghostel = ./packages/ch-evil-ghostel;
        ghostel-funcs = ./packages/ghostel-funcs;
        gh-review = ./packages/gh-review;
        markdown-table-fix = ./packages/markdown-table-fix;
        mermaid-preview = ./packages/mermaid-preview;
        render-dwim = ./packages/render-dwim;
        window-funcs = ./packages/window-funcs;
      };
    };
  };

}
