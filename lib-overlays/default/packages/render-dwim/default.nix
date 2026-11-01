# SPDX-License-Identifier: MIT
{ nemacsBuild, version }:
nemacsBuild {
  pname = "render-dwim";
  inherit version;
  packageRequires = [ ];
  src = ./.;
}
