# SPDX-License-Identifier: MIT
{ lib, ... }:
{
  options = {
    enable = lib.mkEnableOption "emacs configuration bundle";

    packages = lib.mkOption {
      type = lib.types.functionTo (lib.types.functionTo (lib.types.listOf lib.types.package));
      default = _epkgs: _local: [ ];
      description = ''
        Emacs packages required by this bundle's init.
        Function of the top-level Emacs package set and local packages from this module.
      '';
    };

    init = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Elisp merged into the shared `default` init package when this bundle is enabled.
      '';
    };
  };
}
