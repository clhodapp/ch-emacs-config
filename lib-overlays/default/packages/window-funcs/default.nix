# SPDX-License-Identifier: MIT
{ nemacsBuild, version }:
nemacsBuild {
  pname = "window-funcs";
  inherit version;
  packageRequires = [ ];
  src = ./.;
}
