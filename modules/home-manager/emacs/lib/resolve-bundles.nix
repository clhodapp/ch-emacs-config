# SPDX-License-Identifier: MIT
{ lib }:
let
  bundleSpec = import ../bundles/spec.nix;
in
userBundles:
lib.mapAttrs (
  name: specBundle:
  let
    userBundle = userBundles.${name} or { };
  in
  specBundle
  // lib.optionalAttrs (userBundle ? enable) {
    enable = userBundle.enable;
  }
) bundleSpec
