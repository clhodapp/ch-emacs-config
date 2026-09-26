# SPDX-License-Identifier: MIT
{
  evil,
  evil-ghostel,
  ghostel,
  ghostel-funcs,
  mkLocalBuild,
  version,
}:
mkLocalBuild {
  pname = "ch-evil-ghostel";
  inherit version;
  packageRequires = [
    evil
    evil-ghostel
    ghostel
    ghostel-funcs
  ];
  src = ./.;
}
