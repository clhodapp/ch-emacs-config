# SPDX-License-Identifier: MIT
#
# The per-bundle option defaults, one set per bundle the spec defines.
# The spec arrives from the caller so this reads the published value
# rather than a file.
{ bundleSpec }:
{ lib, ... }:
{
  config.ch-emacs-config.emacs.bundles = lib.mapAttrs (_name: bundle: {
    enable = lib.mkDefault bundle.enable;
    init = lib.mkDefault bundle.init;
    packages = lib.mkDefault bundle.packages;
  }) bundleSpec;
}
