# SPDX-License-Identifier: MIT
# A consumer with no flake-parts and no framework: the README's
# first recipe, held as a check. It applies the overlays with a plain
# `import nixpkgs` and builds a home configuration with a plain
# `homeManagerConfiguration`.
#
# Both overlays are applied, in the order the flake's own checks use, so
# the resulting Emacs derivations are the ones the checks already build.
{
  description = "Integration test: plain-flake consumer of ch-emacs-config";

  inputs = {
    parent.url = "path:../../..";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      parent,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          parent.overlays.emacs-packages
          parent.overlays.emacs
        ];
      };
      home = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          parent.modules.homeManager.emacs
          {
            home.username = "plain";
            home.homeDirectory = "/home/plain";
            home.stateVersion = "25.05";
            ch-emacs-config.emacs.enable = true;
          }
        ];
      };
    in
    {
      checks.${system}.plain-consumer =
        # The module's default base package is the overlay's selection.
        assert home.config.ch-emacs-config.emacs.package.outPath == pkgs.ch-emacs-config.emacs.outPath;
        home.activationPackage;
    };
}
