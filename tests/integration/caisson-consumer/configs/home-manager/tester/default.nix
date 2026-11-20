# SPDX-License-Identifier: MIT
#
# The home-manager configuration of the consumer test: the editor as a
# nemacs configuration declared inside it, and the home-manager module
# `emacs` of ch-emacs-config, which names the profile of the editor in
# the desktop entry and `$EDITOR`.
{ closure-lib, ... }:
{ lib, ... }:
{
  imports = [ closure-lib.caisson.modules.homeManager."ch-emacs-config/emacs" ];

  home = {
    username = "tester";
    homeDirectory = "/home/tester";
    stateVersion = "25.05";
  };

  ch-emacs-config.emacs = {
    enable = true;
    # Forces the type of the personal-dictionary option and the merge
    # activation entry.
    jinxPersonalWords = [ "hmcheckword" ];
  };

  caisson.nemacs.configurations.editor = lib.caisson.nemacs.mkConfiguration {
    # The editor leaves the mermaid renderer to `PATH`: it builds from
    # source in this consumer's package set, and the check does not run
    # it.
    configModule.ch-emacs-config.executables.merman = null;
  };
}
