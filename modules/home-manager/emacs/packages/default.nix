# SPDX-License-Identifier: MIT
{
  epkgs,
  epkgsToplevel,
  pkgs,
  version,
  extraInitContent ? "",
  bundleInitContent ? "",
  bundlePackages ? [ ],
}:
let
  scope = import ./scope.nix { inherit epkgs version; };
in
{
  inherit pkgs;
  inherit (scope)
    mkLocalBuild
    evil-ghostel
    ghostel-funcs
    window-funcs
    ;

  default = epkgs.callPackage ./default {
    inherit
      bundleInitContent
      bundlePackages
      extraInitContent
      version
      ;
    inherit (scope) mkLocalBuild;
  };
}
