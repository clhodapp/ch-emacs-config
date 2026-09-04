# SPDX-License-Identifier: MIT
# Selects the Emacs base package for a toolkit variant: the newest major
# in `supportedMajors` that nixpkgs carries as a final release.
#
# nixpkgs ships a new Emacs major as `emacs<NN>-*` before it moves the
# unversioned `emacs-*` attributes, so naming the major is how the
# configuration picks a release up early. A major is listed here once
# the configuration byte-compiles and its checks pass against it; the
# checks build against whatever this selects, so the proposed base and
# the validated base are the same expression.
{ lib, pkgs }:
let
  supportedMajors = [
    "31"
    "30"
  ];

  # Release versions are `<major>.<minor>` with minor >= 1. Pretests are
  # `<major>.0.<nn>` and release candidates carry an `-rcN` suffix, and
  # Nix's version ordering places both ABOVE the release they precede
  # (`compareVersions "31.1-rc1" "31.1"` is 1), so a version comparison
  # alone would accept them.
  isRelease = version: builtins.match "[0-9]+\\.[1-9][0-9]*" version != null;

  candidate =
    variant: major:
    let
      name = "emacs${major}${variant}";
    in
    if pkgs ? ${name} && isRelease pkgs.${name}.version then pkgs.${name} else null;
in
# VARIANT is the attribute suffix: "" for the default build, "-pgtk",
# "-nox".
variant:
let
  found = lib.findFirst (package: package != null) null (map (candidate variant) supportedMajors);
in
if found != null then
  found
else
  throw ''
    ch-emacs-config: none of the supported Emacs majors (${lib.concatStringsSep ", " supportedMajors})
    is present in this nixpkgs as a final release under `emacs<major>${variant}`.
  ''
