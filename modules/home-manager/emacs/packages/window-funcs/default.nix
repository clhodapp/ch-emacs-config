# SPDX-License-Identifier: MIT
{ mkLocalBuild, version }:
mkLocalBuild {
  pname = "window-funcs";
  inherit version;
  packageRequires = [ ];
  src = ./.;
}
