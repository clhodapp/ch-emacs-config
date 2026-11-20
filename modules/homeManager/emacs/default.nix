# SPDX-License-Identifier: MIT
#
# The ch-emacs-config editor in a home-manager configuration. The editor
# is a nemacs configuration declared inside the home-manager
# configuration (`caisson.nemacs.configurations.<name>`), which the
# nemacs module `default` of this flake configures, and which the
# home-manager configuration keeps in a Nix profile of the user. The
# editor carries its fonts and the programs that start its daemon, so
# `nemacs switch` updates all of it without activating this
# home-manager configuration.
#
# What is left here is what only a home-manager configuration can do: the
# desktop entry and `$EDITOR`, which name the profile of the editor, and
# the spell-check dictionaries in the configuration directory of the
# user.
{ closure-lib, ... }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ch-emacs-config.emacs;
  emacsLib = closure-lib.ch-emacs-config;

  inherit (lib.caisson) evalManifest;
  selection = lib.caisson.integrations;

  editorEntry = lib.findFirst (
    entry:
    entry.manifest.outputs.profile.kind == "nemacs"
    && entry.manifest.outputs.profile.name == cfg.configuration
  ) null (selection.profilesActivatedBy evalManifest config.caisson.exports.configurations);

  editor = editorEntry.manifest.value.config;
  bundleEnabled = name: editor.bundles.${name}.enable or false;

  # The directory of the profile of the editor, as a path that does not
  # depend on the shell that reads it: a desktop entry and a cache of
  # it keep the path they were given, and the profile is the one place
  # that always holds the current editor.
  profilePath =
    lib.replaceStrings
      [ "$HOME" ]
      [
        config.home.homeDirectory
      ]
      editorEntry.manifest.outputs.profile.path;

  jinxMergePersonalDict = emacsLib.mkJinxMergePersonalDict { inherit pkgs; };

  jinxDeclaredWords = pkgs.writeText "jinx-declared-words" (
    lib.concatMapStrings (word: word + "\n") (lib.unique cfg.jinxPersonalWords)
  );
in
{
  options.ch-emacs-config.emacs = {
    enable = lib.mkEnableOption "the ch-emacs-config editor";

    configuration = lib.mkOption {
      type = lib.types.str;
      default = "editor";
      description = ''
        The name of the nemacs configuration declared inside this
        home-manager configuration (`caisson.nemacs.configurations`)
        that is the editor. The desktop entry and `$EDITOR` run the
        programs in its profile.
      '';
    };

    jinxPersonalWords = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[^[:space:]]+");
      default = [ ];
      description = ''
        Words merged into enchant's personal dictionary
        (`<xdg.configHome>/enchant/en_US.dic`) at activation. The merge only
        appends words not already present; words saved from jinx at runtime
        (`@` in `jinx-correct`) are kept, never removed or reordered. Takes
        effect only with the jinx bundle enabled.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && !evalManifest.childless) (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = editorEntry != null;
            message = ''
              ch-emacs-config.emacs.enable is set, and this home-manager
              configuration declares no nemacs configuration named
              "${cfg.configuration}". Declare it with
              `caisson.nemacs.configurations.${cfg.configuration}`, or set
              `ch-emacs-config.emacs.configuration` to the name of the one
              that is the editor.
            '';
          }
        ];
      }

      (lib.mkIf (editorEntry != null) (
        lib.mkMerge [
          (lib.mkIf (bundleEnabled "consult-gh") {
            # Emacs finds gh through the pin in the init; this profile copy
            # of the same package serves shells and other gh consumers
            # outside the workspace devshell.
            home.packages = lib.optional (
              editor.ch-emacs-config.executables.gh != null
            ) editor.ch-emacs-config.executables.gh;
          })

          (lib.mkIf (bundleEnabled "jinx") {
            # Enchant scans its per-user config dir for hunspell dictionaries,
            # independent of session env (XDG_DATA_DIRS is cached by GLib before
            # init files could set it); provision the dictionaries there.
            xdg.configFile."enchant/hunspell/en_US.dic".source =
              "${pkgs.hunspellDicts.en_US}/share/hunspell/en_US.dic";
            xdg.configFile."enchant/hunspell/en_US.aff".source =
              "${pkgs.hunspellDicts.en_US}/share/hunspell/en_US.aff";

            # The personal dictionary is runtime-mutable (jinx-correct's save
            # keys rewrite it), so it cannot be a store symlink; converge the
            # declared words in by append-only merge instead.
            home.activation = lib.mkIf (cfg.jinxPersonalWords != [ ]) {
              jinxMergePersonalDict = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                run ${lib.getExe jinxMergePersonalDict} ${jinxDeclaredWords} \
                  ${lib.escapeShellArg "${config.xdg.configHome}/enchant/en_US.dic"}
              '';
            };
          })

          (lib.mkIf (bundleEnabled "daemon") {
            # Desktop launches must not fall back to spawning an unmanaged
            # daemon. The stock emacsclient.desktop passes
            # --alternate-editor= (empty), which forks a bare `emacs --daemon`
            # whenever the socket is unreachable, and the window in which
            # one generation of the daemon replaces another looks exactly
            # like that. That daemon then deletes and rebinds the socket
            # path, stealing the socket from the daemon that holds it.
            # This entry routes launches through the launcher of the
            # editor, which starts the daemon first. The Exec line names
            # the profile of the editor, because desktop caches and pins
            # keep the Exec line they saw when they indexed the entry, and
            # nothing that changes with a generation may appear in it.
            xdg.desktopEntries.emacsclient = {
              name = "Emacs (Client)";
              genericName = "Text Editor";
              comment = "Edit text";
              exec = "${profilePath}/bin/emacsclient-desktop-launcher %F";
              icon = "emacs";
              terminal = false;
              type = "Application";
              categories = [
                "Development"
                "TextEditor"
              ];
              mimeType = [
                "text/english"
                "text/plain"
                "text/x-makefile"
                "text/x-c++hdr"
                "text/x-c++src"
                "text/x-chdr"
                "text/x-csrc"
                "text/x-java"
                "text/x-moc"
                "text/x-pascal"
                "text/x-tcl"
                "text/x-tex"
                "application/x-shellscript"
                "text/x-c"
                "text/x-c++"
              ];
              startupNotify = true;
              settings.StartupWMClass = "Emacs";
            };

            # With a managed daemon in the session, it is the editor. The
            # path in the profile outlives the shells that capture it.
            home.sessionVariables.EDITOR = "${profilePath}/bin/emacsclient-editor-launcher";
          })
        ]
      ))
    ]
  );
}
