# SPDX-License-Identifier: MIT
{
  description = "Unit checks for ch-emacs-config";

  inputs = {
    caisson.url = "github:nix-caisson/caisson";
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
      };
    in
    lib.caisson.flake-parts.mkConfiguration {
      configModule = lib.caisson.flake-parts.mkModule ./configs/flake-parts/unit-tests;
    };
}
