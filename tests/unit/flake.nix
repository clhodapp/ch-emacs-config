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
      lib = caisson.lib.caisson.mkLib {
        inherit (caisson.lib.caisson.pins.flake inputs) sources root;
        projects = {
          inherit caisson;
        };
        configs = lib: lib.caisson.mkModules ./configs;
      };
    in
    lib.caisson.flake-parts.mkTopConfiguration {
      configModule = lib.caisson.configs.flake.unit-tests;
    };
}
