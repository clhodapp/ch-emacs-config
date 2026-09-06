# SPDX-License-Identifier: MIT
#
# The bundle set an init is built from: this configuration's own spec,
# with a consumer's `enable` overrides applied, plus every bundle a
# consumer or a layer above contributed under a name the spec does not
# have. The spec stays the source for its own bundles (their init and
# packages come from here, not from the option), so a consumer can only
# switch one off; a contributed bundle arrives whole through the option
# and is taken as it is.
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
  contributed = lib.filterAttrs (name: _: !(bundleSpec ? ${name})) userBundles;
in
fromSpec // contributed
