# SPDX-License-Identifier: MIT
{
  inputs.caisson.url = "github:nix-caisson/caisson";
  inputs.emacs-overlay.url = "github:nix-community/emacs-overlay";
  inputs.emacs-overlay.inputs.nixpkgs.follows = "nixpkgs";
  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  outputs = { ... }: { };
}
