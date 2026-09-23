# SPDX-License-Identifier: MIT
{ lib }:
let
  enabledNames = bundles: builtins.attrNames (lib.filterAttrs (_name: bundle: bundle.enable) bundles);

  # Emacs baseline first; remaining enabled bundles in alphabetical order.
  # Swap the tail to lib.sort lib.lessThan names when testing plain sorting.
  orderedNames =
    bundles:
    let
      names = enabledNames bundles;
    in
    (lib.optional (lib.elem "emacs" names) "emacs")
    ++ lib.sort lib.lessThan (lib.filter (name: name != "emacs") names);
in
{
  inherit orderedNames;

  initContent =
    bundles:
    let
      names = orderedNames bundles;
    in
    lib.concatStringsSep "\n\n" (map (name: bundles.${name}.init) names);

  packages =
    bundles: epkgs: local:
    lib.concatLists (map (name: bundles.${name}.packages epkgs local) (orderedNames bundles));
}
