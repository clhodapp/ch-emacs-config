# SPDX-License-Identifier: MIT
{

  description = "A declarative Emacs configuration, as a Home Manager module";

  # Honored only when this flake is evaluated directly (`nix build`,
  # `nix flake check`) and the settings are accepted: answer the prompt,
  # or pass `--accept-flake-config` (a non-interactive run otherwise
  # ignores them with a warning). A consumer that takes this flake as an
  # input gets nothing from it and must declare the caches itself. The
  # two upstreams are part of the deal: the clhodapp cache skips
  # uploading paths they already hold.
  nixConfig = {
    extra-substituters = [
      "https://clhodapp.cachix.org"
      "https://nix-community.cachix.org"
      "https://numtide.cachix.org"
    ];
    extra-trusted-public-keys = [
      "clhodapp.cachix.org-1:EW/0conxH0OQyo0o4ub/grdkFspholmQMSnQyj0vrZI="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
    ];
  };

  inputs = {
    caisson.url = "github:nix-caisson/caisson";

    # Plain Emacs package repositories (no flake); pkgs/emacs/overrides.nix
    # builds them into the Emacs package set.
    pr-review.url = "github:clhodapp/emacs-pr-review";
    pr-review.flake = false;
    # ghostel ahead of the nixpkgs/emacs-overlay primary, which still ships
    # 0.53.0; a secondary pin for that one package, on an upstream release
    # tag.  pkgs/emacs/overrides.nix explains it and names when it goes.
    ghostel.url = "github:dakra/ghostel/v0.56.0";
    ghostel.flake = false;

    # MELPA/ELPA package pins.
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    emacs-overlay.inputs.nixpkgs.follows = "nixpkgs";

    # The mermaid renderer behind render-dwim and mermaid-preview, and
    # the mermaid language server the shared server table spawns.
    merman-nix.url = "github:clhodapp/merman-nix";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs =
    inputs@{ caisson, ... }:
    let
      lib = caisson.lib.caisson-core.mkLib {
        inherit inputs;
        namespace = "ch-emacs-config";
        systems = [ "x86_64-linux" ];

        projects = {
          inherit caisson;
        };

        modules = caisson.lib.caisson-core.mkModules ./modules;

        libOverlays = caisson.lib.caisson-core.mkLibOverlays ./lib-overlays;
      };
    in
    lib.caisson.flake-parts.mkConfiguration {
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake-parts/default;
    };

}
