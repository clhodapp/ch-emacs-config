# SPDX-License-Identifier: MIT
{
  ghostel,
  nemacsBuild,
  version,
}:
nemacsBuild {
  pname = "ghostel-funcs";
  inherit version;
  packageRequires = [ ghostel ];
  src = ./.;
}
