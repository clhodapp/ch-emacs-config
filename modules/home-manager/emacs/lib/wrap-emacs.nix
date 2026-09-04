# SPDX-License-Identifier: MIT
{
  lib,
  pkgs,
}:
emacsPackage:
let
  initDir = pkgs.runCommand "ch-emacs-config-emacs-init" { } ''
    mkdir -p $out
    cp ${../emacs-init-dir/early-init.el} $out/early-init.el
  '';
in
pkgs.writeShellScriptBin "emacs" ''
  exec ${emacsPackage}/bin/emacs --init-directory ${initDir} "$@"
''
