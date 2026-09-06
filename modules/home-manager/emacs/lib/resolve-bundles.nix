# SPDX-License-Identifier: MIT
#
# The bundle set an init is built from: this configuration's own spec,
# with a consumer's `enable` overrides applied, plus every bundle the
# option defines under a name the spec does not have (a layer above
# defines its bundles that way). The spec stays the source for its own
# bundles, whose init and packages come from here rather than from the
# option, so a consumer can only switch one of those off; a bundle the
# option defines is taken as it is.
{ lib }:
let
  bundleSpec = import ../bundles/spec.nix;
in
userBundles:
let
  fromSpec = lib.mapAttrs (
    name: specBundle:
    let
      userBundle = userBundles.${name} or { };
    in
    specBundle
    // lib.optionalAttrs (userBundle ? enable) {
      enable = userBundle.enable;
    }
  ) bundleSpec;
  fromOption = lib.filterAttrs (name: _: !(bundleSpec ? ${name})) userBundles;
in
fromSpec // fromOption
