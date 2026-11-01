# SPDX-License-Identifier: MIT
{ nemacsBuild, version }:
nemacsBuild {
  pname = "gh-review";
  inherit version;
  packageRequires = [ ];
  src = ./.;
}
