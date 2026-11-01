# SPDX-License-Identifier: MIT
{ nemacsBuild, version }:
nemacsBuild {
  pname = "markdown-table-fix";
  inherit version;
  packageRequires = [ ];
  src = ./.;
}
