# SPDX-License-Identifier: MIT
{ closure-inputs, ... }:
{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.ch-emacs-config.emacs;
  # Packages consumed as plain (non-flake) inputs; see pkgs/emacs/overrides.nix.
  emacsPackageSources = {
    inherit (closure-inputs) collab-comments parenting pr-review;
  };
  bundleLib = import ./lib/bundles.nix { inherit lib; };
  resolveBundles = import ./lib/resolve-bundles.nix { inherit lib; };
  bundles = resolveBundles cfg.bundles;

  localPackageScope =
    let
      emacsPackage = cfg.package;
      emacsOverrides = import ../../../pkgs/emacs/overrides.nix {
        inherit lib pkgs;
        sources = emacsPackageSources;
      };
      epkgs = (pkgs.emacsPackagesFor emacsPackage).overrideScope emacsOverrides;
      version = emacsPackage.version or "0";
      # The in-tree package scope, extended by any layer built on this
      # one so its bundles can name packages it defines. Fixed point, so
      # an added package can depend on another added package.
      local = lib.fix (
        final:
        lib.foldl' (prev: overlay: prev // overlay final prev) (import ./packages/scope.nix {
          inherit epkgs version;
        }) cfg.localPackageOverlays
      );
      packages = import ./packages {
        inherit
          epkgs
          pkgs
          version
          ;
        epkgsToplevel = epkgs;
        extraInitContent = cfg.extraInitContent;
        bundleInitContent = bundleLib.initContent bundles;
        bundlePackages = bundleLib.packages bundles epkgs local;
      };
    in
    packages // { inherit epkgs local; };

  mergedExtraPackages =
    _epkgs:
    let
      scope = localPackageScope;
    in
    (lib.optionals cfg.enableDefaultPackage [ scope.default ])
    ++ (cfg.extraLocalPackages scope)
    ++ (cfg.extraPackages scope.epkgs);

  daemonBundleEnabled = bundles.daemon.enable or false;

  eglotBundleEnabled = bundles.eglot.enable or false;

  # Shared server table (argv, extensions, settings) — the emacs-side
  # facts (major-mode wiring, languageId pins) stay in the init below.
  languageServers = import ../lib/language-servers.nix pkgs { inherit merman; };

  # Render an argv as elisp string literals for an eglot-server-programs
  # contact list.
  elispStrings = lib.concatMapStringsSep " " (s: ''"${s}"'');

  # Render the table's workspace settings as an eglot plist: attrsets
  # become plists, lists become vectors (JSON arrays), everything else
  # is a string.  The table's settings hold nothing but those shapes.
  toElispPlist =
    v:
    if lib.isAttrs v then
      "(" + lib.concatStringsSep " " (lib.mapAttrsToList (k: v': ":${k} ${toElispPlist v'}") v) + ")"
    else if lib.isList v then
      "[" + lib.concatMapStringsSep " " toElispPlist v + "]"
    else
      ''"${v}"'';

  lspWorkspaceSettings = lib.foldl' lib.recursiveUpdate { } (
    map (s: s.settings or { }) (lib.attrValues languageServers)
  );

  jinxBundleEnabled = bundles.jinx.enable or false;

  jinxMergePersonalDict = import ./lib/jinx-merge-personal-dict.nix { inherit pkgs; };

  jinxDeclaredWords = pkgs.writeText "jinx-declared-words" (
    lib.concatMapStrings (word: word + "\n") (lib.unique cfg.jinxPersonalWords)
  );

  # Headless mermaid renderer for mermaid-preview; the merman language
  # server itself is spawned via the shared table above (same drv).
  # Taken from the flake input rather than `pkgs`: this module is
  # evaluated against the consumer's package set, which carries no
  # overlay of ours.
  merman = closure-inputs.merman.packages.${pkgs.stdenv.hostPlatform.system}.merman;

  mermaidTsModeBundleEnabled = bundles.mermaid-ts-mode.enable or false;

  renderDwimBundleEnabled = bundles.render-dwim.enable or false;

  mcpServerBundleEnabled = bundles.mcp-server.enable or false;

  # Stable-path launcher for the stdio<->emacsclient bridge that ships
  # inside the mcp-server-lib elpa package. MCP clients register this
  # command (e.g. `claude mcp add -s user emacs -- emacs-mcp-stdio`) and
  # keep working across package updates. Defaults target the "emacs"
  # server registered by the mcp-server bundle; explicit flags win
  # because the bridge's argument parser is last-match.
  mcpStdioBridge = pkgs.writeShellApplication {
    name = "emacs-mcp-stdio";
    runtimeInputs = [
      config.programs.emacs.finalPackage
      pkgs.coreutils
    ];
    text = ''
      bridge=(${localPackageScope.epkgs.mcp-server-lib}/share/emacs/site-lisp/elpa/mcp-server-lib-*/emacs-mcp-stdio.sh)
      exec bash "''${bridge[0]}" \
        --init-function=ch-emacs-config-mcp-server-start \
        --server-id=emacs \
        "$@"
    '';
  };

  claudeQueueBundleEnabled = bundles.claude-queue.enable or false;

  consultGhBundleEnabled = bundles.consult-gh.enable or false;

  earlyInitEl = builtins.readFile ./emacs-init-dir/early-init.el;

  # Build-time fallback for the launchers' runtime hash derivation:
  # 12-char store hash of this generation's Emacs — the systemd
  # instance name ("/nix/store/" is 11 chars).  The canonical
  # derivation is lib/emacs-gen-hash.sh, shared by the launchers and
  # the activation script; this value only serves a launch happening
  # while the profile is missing or foreign.
  emacsGenHash = builtins.substring 11 12 (toString config.programs.emacs.finalPackage);

  # Launchers behind the desktop entry and $EDITOR.  Everything a
  # launch depends on is resolved at RUN time through the live profile
  # — the daemon instance hash and the emacsclient binary — with this
  # build's paths only as fallback, so a cached copy of the script
  # from ANY generation still drives the CURRENT daemon.  That
  # staleness is real: desktop caches (ksycoca), taskbar pins, and
  # $EDITOR values in long-lived shells all capture whatever they saw
  # at index time and never notice profile switches (a store-symlink
  # swap changes no watched mtime).  Field incident 2026-08-09: a
  # five-day-old plasmashell cache Exec'd a launcher whose baked
  # instance was long gone — every launch start-failed its unit, then
  # fell through to the socket.  For the same reason the scripts are
  # installed into the profile and referenced by their stable profile
  # path, which also keeps cached references alive after old
  # generations are GC'd.
  emacsclientLaunchPrelude = ''
    ${builtins.readFile ./lib/emacs-gen-hash.sh}
    profile=${lib.escapeShellArg config.home.profileDirectory}
    gen_hash=$(emacs_gen_hash "$profile/bin/emacs") || gen_hash=${emacsGenHash}
    systemctl --user start "emacs-daemon@$gen_hash.service" || true
    client="$profile/bin/emacsclient"
    [ -x "$client" ] || client=${config.programs.emacs.finalPackage}/bin/emacsclient
  '';

  # Desktop-launch path: make sure the current generation's daemon
  # instance is up (Type=notify start blocks until the socket is
  # bound; a no-op when it already runs), then connect.  No
  # --alternate-editor fallback on purpose.
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

  # $EDITOR path: same custody rules as desktop launches, but blocking
  # (callers like git wait for C-x #) and frame-reusing — from a
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
  options.ch-emacs-config.emacs = {
    enable = lib.mkEnableOption "shared emacs configuration";

    package = lib.mkOption {
      type = lib.types.package;
      default =
        pkgs.ch-emacs-config.emacs or (throw ''
          ch-emacs-config.emacs.package has no default because `pkgs` lacks
          `pkgs.ch-emacs-config.emacs`: apply this flake's `overlays.emacs` to
          the nixpkgs instance home-manager uses, or set the option to an
          Emacs package explicitly.
        '');
      defaultText = lib.literalExpression "pkgs.ch-emacs-config.emacs";
      description = ''
        Base Emacs package used to build the configured package set and init
        package version. Set this before the module builds `programs.emacs`.

        The default is the Emacs this configuration is validated against,
        provided by the flake's `overlays.emacs` as `pkgs.ch-emacs-config.emacs`
        (the same overlay also provides `emacs-pgtk` and `emacs-nox`).
      '';
    };

    enableDefaultPackage = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the default shared emacs package from this flake.";
    };

    extraPackages = lib.mkOption {
      type = lib.types.functionTo (lib.types.listOf lib.types.package);
      default = _epkgs: [ ];
      description = "Additional emacs packages function appended to the module defaults.";
    };

    extraLocalPackages = lib.mkOption {
      type = lib.types.functionTo (lib.types.listOf lib.types.package);
      default = _localPackages: [ ];
      description = "Additional packages from the local package scope exported by this module.";
    };

    localPackageOverlays = lib.mkOption {
      type = lib.types.listOf (lib.types.functionTo (lib.types.functionTo lib.types.attrs));
      default = [ ];
      example = lib.literalExpression ''
        [ (final: prev: { my-package = final.mkLocalBuild { ... }; }) ]
      '';
      description = ''
        Overlays extending the local package scope, so a layer built on
        this configuration can add packages its own bundles reference by
        name. Each is `final: prev:` over the scope, which carries
        `mkLocalBuild` for building an in-tree package the same way this
        module does.
      '';
    };

    overrides = lib.mkOption {
      type = lib.types.functionTo (lib.types.functionTo lib.types.attrs);
      default = _self: _super: { };
      description = ''
        Overrides for the Emacs package set, forwarded to `programs.emacs.overrides`.
      '';
    };

    extraInitContent = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Additional Elisp appended to the shared `default` init package after the
        baseline `default.el`. Use `lib.mkAfter` in downstream modules to extend
        without replacing the shared config.
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

    bundles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ./bundle-module.nix);
      default = { };
      description = ''
        Init and package bundles merged into the shared `default` init package.
        Enabled bundle init is ordered with `emacs` first, then alphabetical.
      '';
    };
  };

  imports = [
    ./bundles/default.nix
  ];

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        programs.emacs.overrides = lib.mkDefault (
          lib.composeExtensions cfg.overrides (
            import ../../../pkgs/emacs/overrides.nix {
              inherit lib pkgs;
              sources = emacsPackageSources;
            }
          )
        );

        home.file = {
          ".emacs.d/early-init.el".text = earlyInitEl;
          ".config/emacs/early-init.el".text = earlyInitEl;
        };

        programs.emacs = {
          enable = lib.mkDefault true;
          package = lib.mkDefault cfg.package;
          extraPackages = lib.mkDefault mergedExtraPackages;
        };
      }
      (lib.mkIf mcpServerBundleEnabled ({
        home.packages = [ mcpStdioBridge ];

        # Nix-baked headless renderer for the present tool's mermaid
        # mode; without it the init's bare-name default needs an mmdc
        # on PATH, which nothing installs.
        ch-emacs-config.emacs.extraInitContent = lib.mkAfter ''
          (setq ch-emacs-config-mcp-mermaid-command (list "${lib.getExe merman}" "mmdc"))
        '';
      }))
      (lib.mkIf consultGhBundleEnabled {
        # Emacs resolves gh through the packages-deps profile (nixpkgs
        # consult-gh propagates it); this profile copy serves shells
        # and other gh consumers outside the workspace devshell.
        home.packages = [ pkgs.gh ];
      })
      (lib.mkIf jinxBundleEnabled {
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
      (lib.mkIf eglotBundleEnabled {
        ch-emacs-config.emacs.extraInitContent = lib.mkAfter ''
          ;; Language servers from the shared table (../lib/language-servers.nix),
          ;; store-pinned for GUI Emacs sessions without HM PATH.
          ;; Prepended entries win over eglot's built-in server table.
          (with-eval-after-load 'eglot
            (add-to-list 'eglot-server-programs
                         '(nix-ts-mode . (${elispStrings languageServers.nil.cmd})))
            (add-to-list 'eglot-server-programs
                         '(python-base-mode . (${elispStrings languageServers.ty-ruff.cmd})))
            (add-to-list 'eglot-server-programs
                         '(markdown-ts-mode . (${elispStrings languageServers.marksman.cmd})))
            (add-to-list 'eglot-server-programs
                         '(((js-base-mode :language-id "javascript")
                            (tsx-ts-mode :language-id "typescriptreact")
                            (typescript-ts-mode :language-id "typescript"))
                           . (${elispStrings languageServers.typescript-language-server.cmd})))
            (add-to-list 'eglot-server-programs
                         '((json-ts-mode js-json-mode)
                           . (${elispStrings languageServers.vscode-json-language-server.cmd})))
            (add-to-list 'eglot-server-programs
                         '(mermaid-ts-mode . (${elispStrings languageServers.merman-lsp.cmd}))))
          (setq-default eglot-workspace-configuration
                        '${toElispPlist lspWorkspaceSettings})
        '';
      })
      (lib.mkIf mermaidTsModeBundleEnabled {
        ch-emacs-config.emacs.extraInitContent = lib.mkAfter ''
          ;; Nix-baked headless renderer path for mermaid-preview.
          (use-package mermaid-preview
            :demand t
            :config
            (setq mermaid-preview-command (list "${lib.getExe merman}" "mmdc")))
        '';
      })
      (lib.mkIf renderDwimBundleEnabled ({
        ch-emacs-config.emacs.extraInitContent = lib.mkAfter ''
          ;; Nix-baked renderer and detector paths for render-dwim.
          (use-package render-dwim
            :demand t
            :config
            (setq render-dwim-mermaid-command (list "${lib.getExe merman}" "mmdc"))
            (setq render-dwim-detect-command (list "${lib.getExe merman}" "detect")))
        '';
      }))
      (lib.mkIf daemonBundleEnabled {
        # The launchers live in the profile so the desktop entry, pins,
        # and $EDITOR can reference them by stable path (rationale at
        # their definition above).
        home.packages = [
          emacsclientDesktopLauncher
          emacsclientEditorLauncher
        ];

        # Desktop launches must never fall back to spawning an unmanaged
        # daemon: the stock emacsclient.desktop passes --alternate-editor=
        # (empty), which forks a bare `emacs --daemon` whenever the canonical
        # socket is unreachable — exactly what the rotation window looks
        # like — and that rogue then deletes and rebinds the socket path,
        # stealing custody from the unit daemon and swallowing later taints.
        # This entry displaces the package's own one in the profile (same
        # desktop-file id; xdg.desktopEntries installs via home.packages)
        # and routes launches through the runtime-resolving launcher's
        # stable profile path — desktop caches and pins keep whatever
        # Exec they saw at index time, so nothing per-generation may
        # appear in it.
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

        # With a managed daemon in the session, it is the editor.  The
        # stable profile path outlives the shells that capture it.
        home.sessionVariables.EDITOR = "${config.home.profileDirectory}/bin/emacsclient-editor-launcher";

        # Template unit shared by all generation instances.
        # %i is the 12-char store hash of the Emacs package for this generation,
        # used only as a stable systemd instance name for tracking; the daemon
        # itself always owns the canonical "server" socket name.
        systemd.user.services."emacs-daemon@" = {
          Unit = {
            Description = "Emacs daemon (generation %i)";
            After = [ "graphical-session-pre.target" ];
            PartOf = [ "graphical-session.target" ];
            # ExecStart bakes in a per-generation store path, so this unit
            # file changes every switch; by default sd-switch would then
            # restart all running instances — killing the live daemon.
            # keep-old leaves running instances untouched; the activation
            # script below starts the new generation's instance itself.
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Type = "notify";
            # Always bind to the canonical "server" socket; the activation
            # script mv's the old socket aside before starting this instance.
            # Use the baked-in Nix store path — ~/.nix-profile may not be set
            # up when the daemon first starts.
            ExecStart = "${config.programs.emacs.finalPackage}/bin/emacs --fg-daemon=server";
            Restart = "no";
            StandardInput = "null";
          };
          # Not WantedBy anything — activation script starts the right instance.
        };

        # At each HM switch, if the Emacs package changed: taint the old daemon,
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
            ${config.programs.emacs.finalPackage}/bin/emacsclient \
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

            # Retire the old daemon (if reachable): rename its socket to a
            # per-instance drain name first — closing the window where new
            # clients still land on it — then taint it through the renamed
            # socket so it adopts the drain name and starts its drain timer.
            if [ -S "$_canonical" ]; then
              _old_pid=$(${config.programs.emacs.finalPackage}/bin/emacsclient \
                --socket-name="$_canonical" --eval '(emacs-pid)' 2>/dev/null \
                | tr -cd '0-9' || true)
              if [ -n "$_old_pid" ]; then
                _drain_name="server-drain-$_old_pid"
                mv "$_canonical" "$_socket_dir/$_drain_name" 2>/dev/null || true
                ${config.programs.emacs.finalPackage}/bin/emacsclient \
                  --socket-name="$_socket_dir/$_drain_name" \
                  --eval "(when (fboundp 'ch-emacs-config-daemon-taint) (ch-emacs-config-daemon-taint \"$_drain_name\"))" \
                  2>/dev/null || true
              else
                # Nothing answers on the canonical path: a stale socket file
                # left by a crashed or killed daemon.  Remove it — a stale
                # file here makes emacsclient fail, and desktop fallbacks
                # would then spawn unmanaged daemons.
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
  );
}
