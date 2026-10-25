# SPDX-License-Identifier: MIT
# consult-ghostel, built from the ghostel source tree.
#
# ghostel ships this file under extensions/, like evil-ghostel, and its
# own recipe installs only the core elisp.  MELPA publishes it as a
# separate recipe, but building it here from `ghostel.src' keeps it at
# the same version as the core: it calls internal ghostel helpers for
# soft wraps and the input region directly.
{
  lib,
  melpaBuild,
  src,
  version,
  consult,
  ghostel,
}:
melpaBuild {
  pname = "consult-ghostel";
  inherit src version;

  files = ''("extensions/consult-ghostel/consult-ghostel.el")'';

  packageRequires = [
    consult
    ghostel
  ];

  meta = {
    homepage = "https://github.com/dakra/ghostel";
    description = "Consult integration for ghostel";
    license = lib.licenses.gpl3Plus;
  };
}
