# SPDX-License-Identifier: MIT
{ nemacsBuild, version }:
nemacsBuild {
  pname = "mermaid-preview";
  inherit version;
  packageRequires = [ ];
  src = ./.;
}
