# SPDX-License-Identifier: MIT
{
  description = "Unit checks for ch-emacs-config";

  inputs = {
    caisson.url = "github:nix-caisson/caisson";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs =
    inputs@{ caisson, ... }:
    let
      lib = caisson.lib.caisson-core.mkLib {
        inherit inputs;
        projects = {
          inherit caisson;
        };
      };
    in
    lib.caisson.flake-parts.mkConfiguration {
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake-parts/unit-tests;
    };
}
