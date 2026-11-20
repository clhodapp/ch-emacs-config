# SPDX-License-Identifier: MIT
# A caisson consumer of ch-emacs-config: a flake that lists it in
# `projects` and declares a home-manager configuration with the editor
# inside it, as a nemacs configuration. The check builds the
# home-manager configuration and asserts what the parent reads from the
# editor: the Nix profile of the editor, the desktop entry and `$EDITOR`
# that name it, and the fonts and launchers the editor carries.
{
  description = "Integration test: a caisson consumer of ch-emacs-config";

  inputs = {
    parent.url = "path:../../..";
    caisson.url = "github:nix-caisson/caisson";
    nemacs.url = "github:clhodapp/nemacs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      caisson,
      nemacs,
      parent,
      nixpkgs,
      ...
    }:
    let
      system = "x86_64-linux";
      lib = caisson.lib.caisson.mkLib {
        inherit (caisson.lib.caisson.pins.flake inputs) dependencies root;
        defaultEcosystemSrc = dependencies: { nixpkgs-lib = dependencies.nixpkgs; };
        name = "consumer";
        systems = [ system ];
        projects = {
          inherit caisson nemacs;
          ch-emacs-config = parent;
        };
        configs = lib: lib.caisson.mkModules ./configs;
        pkgSets = lib: lib.caisson.nixpkgs.mkConfigurations { };
      };
      # The home-manager configuration takes its module from the
      # registry by its name, `configs/homeManager/tester`.
      top = lib.caisson.flake-parts.mkTopConfiguration {
        configModule =
          { lib, ... }:
          {
            caisson.home-manager.configurations.tester = lib.caisson.home-manager.mkConfiguration { };
          };
      };
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (nixpkgs.lib) hasInfix;
      home = top.homeConfigurations.tester.config;
      # The editor as the home-manager configuration reads it from its
      # exports.
      editor =
        (nixpkgs.lib.findFirst (
          entry: entry.manifest.outputs.profile.kind == "nemacs"
        ) null home.caisson.exports.configurations).manifest.outputs;
      profileDir = "/home/tester/.local/state/caisson/profiles/nemacs/editor";
    in
    top
    // {
      checks = (top.checks or { }) // {
        ${system} = (top.checks.${system} or { }) // {
          activation =
            # The editor is the nemacs configuration declared inside the
            # home-manager configuration, and the profile that holds it is
            # a profile of the user.
            assert editor.profile.path == "$HOME/.local/state/caisson/profiles/nemacs/editor";
            # The desktop entry and `$EDITOR` run the launchers of the
            # editor by the path of the profile.
            assert
              home.xdg.desktopEntries.emacsclient.exec == "${profileDir}/bin/emacsclient-desktop-launcher %F";
            assert home.home.sessionVariables.EDITOR == "${profileDir}/bin/emacsclient-editor-launcher";
            # The profile is on `PATH`, and its fonts are in fontconfig.
            assert builtins.elem "$HOME/.local/state/caisson/profiles/nemacs/editor/bin" home.home.sessionPath;
            assert hasInfix "profiles/nemacs/editor/share/fonts"
              home.xdg.configFile."fontconfig/conf.d/60-caisson-profiles.conf".text;
            # The editor is not installed into the home-manager profile.
            assert !(builtins.elem editor.package home.home.packages);
            pkgs.runCommand "caisson-consumer-activation" { } ''
              # The editor carries the programs that start its daemon.
              test -x ${editor.package}/bin/emacsclient-desktop-launcher
              test -x ${editor.package}/bin/emacsclient-editor-launcher
              test -x ${editor.package}/bin/ch-emacs-config-daemon-ensure
              test -d ${editor.package}/share/fonts
              ln -s ${home.home.activationPackage} $out
            '';
        };
      };
    };
}
