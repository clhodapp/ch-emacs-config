# SPDX-License-Identifier: MIT
{ mkLocalBuild, version }:
mkLocalBuild {
  pname = "markdown-hide-markup";
  inherit version;
  packageRequires = [ ];
  src = ./.;
}
