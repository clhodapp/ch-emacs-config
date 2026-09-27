# SPDX-License-Identifier: MIT
{
  ghostel,
  mkLocalBuild,
  version,
}:
mkLocalBuild {
  pname = "ghostel-funcs";
  inherit version;
  packageRequires = [ ghostel ];
  src = ./.;
}
