# SPDX-License-Identifier: MIT
{ mkLocalBuild, version }:
mkLocalBuild {
  pname = "markdown-table-fix";
  inherit version;
  packageRequires = [ ];
  src = ./.;
}
