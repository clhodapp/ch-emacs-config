# SPDX-License-Identifier: MIT
{ mkLocalBuild, version }:
mkLocalBuild {
  pname = "gh-review";
  inherit version;
  packageRequires = [ ];
  src = ./.;
}
