# SPDX-License-Identifier: MIT
#
# The per-bundle option defaults, one set per bundle the spec defines.
# The spec arrives from the caller so this reads the published value
# rather than a file.
{ bundleSpec }:
{ lib, ... }:
{
  options = lib.mkMerge (
    lib.mapAttrsToList (name: bundle: {
      "ch-emacs-config.emacs.bundles.${name}.enable" = lib.mkDefault bundle.enable;
      "ch-emacs-config.emacs.bundles.${name}.init" = lib.mkDefault bundle.init;
      "ch-emacs-config.emacs.bundles.${name}.packages" = lib.mkDefault bundle.packages;
    }) bundleSpec
  );
}
