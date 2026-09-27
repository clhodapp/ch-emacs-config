# SPDX-License-Identifier: MIT
{ mkLocalBuild, version }:
mkLocalBuild {
  pname = "render-dwim";
  inherit version;
  packageRequires = [ ];
  src = ./.;
}
