# SPDX-License-Identifier: MIT
#
# The local ch-emacs-config library namespace: the values this
# configuration publishes, for the modules here and for a layer built on
# top of them. Every reader takes them from the composed library, so
# each value has one name and the directory layout of this repo stays
# internal.
#
# The three files sit beside this overlay, which owns them. Each reaches
# back into the module tree for the pieces it renders: the package scope
# stitches together the executables table, the bundle helpers and the
# package set, and the bundle spec reads the init files. Those are
# implementation details of the published values rather than a consumer
# crossing the tree.
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
    };
  };

}
