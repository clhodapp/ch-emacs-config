# SPDX-License-Identifier: MIT
{ mkLocalBuild, version }:
mkLocalBuild {
  pname = "mermaid-preview";
  inherit version;
  packageRequires = [ ];
  src = ./.;
}
