# SPDX-License-Identifier: MIT
{

  description = "A declarative Emacs configuration, as a Home Manager module";

  inputs = {
    caisson.url = "github:nix-caisson/caisson";

    # Plain Emacs package repositories (no flake); pkgs/emacs/overrides.nix
    # builds them into the Emacs package set.
    pr-review.url = "github:clhodapp/emacs-pr-review";
    pr-review.flake = false;

    # MELPA/ELPA package pins.
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    emacs-overlay.inputs.nixpkgs.follows = "nixpkgs";

    # The mermaid renderer behind render-dwim and mermaid-preview, and
    # the mermaid language server the shared server table spawns.
    merman.url = "github:clhodapp/merman";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    inputs@{ caisson, ... }:
    let
      lib = caisson.lib.caisson-core.mkLib {
        inherit inputs;

        projects = {
          inherit caisson;
        };

        modules = lib: {
          flake = {
            default = lib.caisson.mkFlakeModule ./modules/flake-parts/default;
            emacs = lib.caisson.mkFlakeModule ./modules/flake-parts/emacs;
          };
          homeManager = import ./modules/home-manager {
            inherit lib;
          };
        };
      };
    in
    lib.caisson.mkFlake {
      name = "ch-emacs-config";
      configModule = lib.caisson.mkFlakeModule ./configs/flake-parts/default;
    };

}
