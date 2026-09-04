# SPDX-License-Identifier: MIT
{ lib, ... }:
let
  spec = import ./spec.nix;
in
{
  options = lib.mkMerge (
    lib.mapAttrsToList (name: bundle: {
      "ch-emacs-config.emacs.bundles.${name}.enable" = lib.mkDefault bundle.enable;
      "ch-emacs-config.emacs.bundles.${name}.init" = lib.mkDefault bundle.init;
      "ch-emacs-config.emacs.bundles.${name}.packages" = lib.mkDefault bundle.packages;
    }) spec
  );
}
