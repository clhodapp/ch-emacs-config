# SPDX-License-Identifier: MIT
{
  evil,
  evil-ghostel,
  ghostel,
  ghostel-funcs,
  nemacsBuild,
  version,
}:
nemacsBuild {
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
