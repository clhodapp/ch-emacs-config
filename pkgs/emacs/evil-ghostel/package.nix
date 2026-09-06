# SPDX-License-Identifier: MIT
# evil-ghostel, built from ghostel's own source tree.
#
# ghostel ships this file under extensions/, and its MELPA recipe
# (`:defaults') installs only the top-level elisp, so the upstream
# emacsPackages.ghostel does not carry it. Building it here from
# `ghostel.src' keeps the two at one version: this package calls into
# ghostel's internals, and a version skew between them is exactly what
# the vendored copy this replaces was working around.
{
  lib,
  melpaBuild,
  src,
  version,
  evil,
  ghostel,
}:
melpaBuild {
  pname = "evil-ghostel";
  inherit src version;

  files = ''("extensions/evil-ghostel/evil-ghostel.el")'';

  packageRequires = [
    evil
    ghostel
  ];

  meta = {
    homepage = "https://github.com/dakra/ghostel";
    description = "Evil-mode integration for ghostel";
    license = lib.licenses.gpl3Plus;
  };
}
