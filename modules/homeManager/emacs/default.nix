# SPDX-License-Identifier: MIT
#
# The ch-emacs-config editor in a Home Manager configuration. The editor
# itself is the nemacs configuration in `programs.nemacs.settings`,
# which this module seeds with the nemacs module `default`; what is
# left here is what only a home can do: install the fonts the init
# names, provision the spell-check dictionaries, run the daemon and its
# launchers.
{ closure-lib, ... }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ch-emacs-config.emacs;
  registry = closure-lib.caisson.libManifest.modules;
  emacsLib = closure-lib.ch-emacs-config;

  settings = config.programs.nemacs.settings;
  editor = settings.build.package;
  bundleEnabled = name: settings.bundles.${name}.enable or false;

  jinxMergePersonalDict = emacsLib.mkJinxMergePersonalDict { inherit pkgs; };

  jinxDeclaredWords = pkgs.writeText "jinx-declared-words" (
    lib.concatMapStrings (word: word + "\n") (lib.unique cfg.jinxPersonalWords)
  );

  # Build-time fallback for the launchers' runtime hash derivation: the
  # 12-character store hash of this generation's editor, which is the
  # systemd instance name ("/nix/store/" is 11 characters). The
  # canonical derivation is lib/emacs-gen-hash.sh, shared by the
  # launchers and the activation script; this value only serves a launch
  # that happens while the profile is missing or foreign.
  emacsGenHash = builtins.substring 11 12 (toString editor);

  # Launchers behind the desktop entry and $EDITOR. Everything a launch
  # depends on is resolved at run time through the live profile (the
  # daemon instance hash and the emacsclient binary), with this build's
  # paths only as fallback, so a cached copy of the script from any
  # generation still drives the current daemon. That staleness is real:
  # desktop caches (ksycoca), taskbar pins, and $EDITOR values in
  # long-lived shells all capture whatever they saw at index time and
  # never notice profile switches, because a store-symlink swap changes
  # no watched mtime. Field incident 2026-08-09: a five-day-old
  # plasmashell cache ran a launcher whose baked instance was long gone,
  # so every launch failed to start its unit and then fell through to the
  # socket. For the same reason the scripts are installed into the
  # profile and referenced by their stable profile path, which also keeps
  # cached references alive after old generations are collected.
  emacsclientLaunchPrelude = ''
    ${builtins.readFile ./lib/emacs-gen-hash.sh}
    profile=${lib.escapeShellArg config.home.profileDirectory}
    gen_hash=$(emacs_gen_hash "$profile/bin/emacs") || gen_hash=${emacsGenHash}
    systemctl --user start "emacs-daemon@$gen_hash.service" || true
    client="$profile/bin/emacsclient"
    [ -x "$client" ] || client=${editor}/bin/emacsclient
  '';

  # Desktop-launch path: make sure the current generation's daemon
  # instance is up (a Type=notify start blocks until the socket is bound,
  # and is a no-op when it already runs), then connect. There is no
  # --alternate-editor fallback, on purpose.
  emacsclientDesktopLauncher = pkgs.writeShellApplication {
    name = "emacsclient-desktop-launcher";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
    ];
    text = ''
      ${emacsclientLaunchPrelude}
      exec "$client" \
        --socket-name="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/emacs/server" \
        --create-frame --no-wait "$@"
    '';
  };

  # $EDITOR path: the same custody rules as desktop launches, but
  # blocking (callers like git wait for C-x #) and frame-reusing. From a
  # terminal inside the session the buffer lands in the live frame
  # rather than spawning a new one.
  emacsclientEditorLauncher = pkgs.writeShellApplication {
    name = "emacsclient-editor-launcher";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
    ];
    text = ''
      ${emacsclientLaunchPrelude}
      exec "$client" \
        --socket-name="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/emacs/server" "$@"
    '';
  };
in
{
  imports = [ registry.homeManager."nemacs/nemacs" ];

  options.ch-emacs-config.emacs = {
    enable = lib.mkEnableOption "the ch-emacs-config editor";

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

  config = lib.mkMerge [
    # Outside the enable guard: a layer above reads what the settings
    # build (the package set, a bundle's init), and asking it to enable
    # the editor first would be an ordering trap.
    { programs.nemacs.settings.imports = [ registry.nemacs.default ]; }

    (lib.mkIf cfg.enable (
      lib.mkMerge [
        { programs.nemacs.enable = lib.mkDefault true; }
        (lib.mkIf (bundleEnabled "consult-gh") {
          # Emacs finds gh through the pin in the init; this profile copy
          # of the same package serves shells and other gh consumers
          # outside the workspace devshell.
          home.packages = lib.optional (
            settings.ch-emacs-config.executables.gh != null
          ) settings.ch-emacs-config.executables.gh;
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
        (
          let
            fonts = lib.filter (font: font != null) (lib.attrValues settings.ch-emacs-config.fonts);
          in
          {
            # Emacs resolves a font family through fontconfig, which reads
            # the profile, so every font the init names is installed here.
            # fontconfig has to be on for the profile's fonts directory to
            # be scanned at all.
            home.packages = fonts;
            fonts.fontconfig.enable = lib.mkDefault (fonts != [ ]);
          }
        )
        (lib.mkIf (bundleEnabled "daemon") {
          # The launchers live in the profile so the desktop entry, pins,
          # and $EDITOR can reference them by stable path (rationale at
          # their definition above).
          home.packages = [
            emacsclientDesktopLauncher
            emacsclientEditorLauncher
          ];

          # Desktop launches must not fall back to spawning an unmanaged
          # daemon. The stock emacsclient.desktop passes
          # --alternate-editor= (empty), which forks a bare `emacs --daemon`
          # whenever the canonical socket is unreachable, and the rotation
          # window looks exactly like that. That rogue daemon then deletes
          # and rebinds the socket path, stealing custody from the unit
          # daemon and swallowing later taints. This entry displaces the
          # package's own one in the profile (same desktop-file id;
          # xdg.desktopEntries installs via home.packages) and routes
          # launches through the stable profile path of the launcher that
          # resolves at run time. Desktop caches and pins keep whatever Exec
          # they saw at index time, so nothing per-generation may appear in
          # it.
          xdg.desktopEntries.emacsclient = {
            name = "Emacs (Client)";
            genericName = "Text Editor";
            comment = "Edit text";
            exec = "${config.home.profileDirectory}/bin/emacsclient-desktop-launcher %F";
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
          # stable profile path outlives the shells that capture it.
          home.sessionVariables.EDITOR = "${config.home.profileDirectory}/bin/emacsclient-editor-launcher";

          # Template unit shared by all generation instances.
          # %i is the 12-char store hash of the editor for this generation,
          # used only as a stable systemd instance name for tracking; the daemon
          # itself always owns the canonical "server" socket name.
          systemd.user.services."emacs-daemon@" = {
            Unit = {
              Description = "Emacs daemon (generation %i)";
              After = [ "graphical-session-pre.target" ];
              PartOf = [ "graphical-session.target" ];
              # ExecStart bakes in a per-generation store path, so this unit
              # file changes every switch; by default sd-switch would then
              # restart all running instances, killing the live daemon.
              # keep-old leaves running instances untouched; the activation
              # script below starts the new generation's instance itself.
              X-SwitchMethod = "keep-old";
            };
            Service = {
              Type = "notify";
              # Always bind to the canonical "server" socket; the activation
              # script moves the old socket aside before starting this
              # instance. The store path is baked in because ~/.nix-profile
              # may not be set up when the daemon first starts.
              ExecStart = "${editor}/bin/emacs --fg-daemon=server";
              Restart = "no";
              StandardInput = "null";
            };
            # Not WantedBy anything: the activation script starts the right instance.
          };

          # At each HM switch, if the editor changed: taint the old daemon,
          # move its socket aside, then start the new generation's instance.
          home.activation.emacsRotateDaemon = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
            ${builtins.readFile ./lib/emacs-gen-hash.sh}
            _emacs_bin="$newGenPath/home-path/bin/emacs"
            _emacs_hash=$(emacs_gen_hash "$_emacs_bin") || _emacs_hash="default"
            _socket_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/emacs"
            _canonical="$_socket_dir/server"

            # Sweep drain sockets whose daemon is gone (a draining daemon
            # deletes its own socket on clean exit, but not on SIGKILL).
            for _drain_sock in "$_socket_dir"/server-drain-*; do
              [ -S "$_drain_sock" ] || continue
              ${editor}/bin/emacsclient \
                --socket-name="$_drain_sock" --eval t >/dev/null 2>&1 \
                || rm -f "$_drain_sock"
            done

            # Check whether the running instance already matches this generation.
            _running=$(${pkgs.systemd}/bin/systemctl --user show \
              "emacs-daemon@$_emacs_hash.service" --property=ActiveState --value 2>/dev/null || echo inactive)

            # Both branches announce themselves unconditionally: a switch
            # that does NOT rotate looks identical to one that does from
            # the outside (frames stay up either way), and a user who just
            # switched expecting new Emacs config reads the daemon's
            # continued residency as a rotation failure unless told the
            # generation is unchanged (field incident 2026-08-09).
            if [ "$_running" = "active" ]; then
              noteEcho "Emacs unchanged (daemon generation $_emacs_hash already active); not rotating"
            else
              noteEcho "Rotating Emacs daemon to generation $_emacs_hash"

              # Retire the old daemon (if reachable). Its socket is renamed to
              # a per-instance drain name first, which closes the window where
              # new clients still land on it, and then it is tainted through
              # the renamed socket so it adopts the drain name and starts its
              # drain timer.
              if [ -S "$_canonical" ]; then
                _old_pid=$(${editor}/bin/emacsclient \
                  --socket-name="$_canonical" --eval '(emacs-pid)' 2>/dev/null \
                  | tr -cd '0-9' || true)
                if [ -n "$_old_pid" ]; then
                  _drain_name="server-drain-$_old_pid"
                  mv "$_canonical" "$_socket_dir/$_drain_name" 2>/dev/null || true
                  ${editor}/bin/emacsclient \
                    --socket-name="$_socket_dir/$_drain_name" \
                    --eval "(when (fboundp 'ch-emacs-config-daemon-taint) (ch-emacs-config-daemon-taint \"$_drain_name\"))" \
                    2>/dev/null || true
                else
                  # Nothing answers on the canonical path: a stale socket file
                  # left by a crashed or killed daemon. Remove it, because a
                  # stale file here makes emacsclient fail, and desktop
                  # fallbacks would then spawn unmanaged daemons.
                  rm -f "$_canonical"
                fi
              fi

              # Start the new generation's daemon instance.
              mkdir -p "$_socket_dir"
              chmod 700 "$_socket_dir"
              ${pkgs.systemd}/bin/systemctl --user start "emacs-daemon@$_emacs_hash.service" || true
            fi
          '';
        })
      ]
    ))
  ];
}
