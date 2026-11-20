# SPDX-License-Identifier: MIT
#
# The checks of ch-emacs-config: a flake-parts configuration declared
# inside the flake-parts caisson top (configs/flake/ch-emacs-config),
# whose dependencies are those of the caisson top with the pins of
# tests/dependencies beside them. The caisson top gathers the checks
# declared here into its `checks` output. A flake that lists
# ch-emacs-config as an input reads nothing of this configuration, so it
# locks none of the pins of tests/dependencies.
#
# `inputs` are those dependencies. `self` is the flake of this
# configuration, and `self.outPath` is the source tree of
# ch-emacs-config. The package set the checks build against is the
# `default` package config declared on mkLib, with the default
# selection of the registry: `default` after the `emacs-packages` entry
# it imports, and `merman-nix/default`. The checks then validate what a
# consumer applying `ch-emacs-config/default` gets.
{ closure-lib, ... }:
{
  inputs,
  lib,
  self,
  ...
}:
let

  # The flake of ch-emacs-config, evaluated from source by
  # `lib.caisson.callConsumerFlake` over the inputs of this
  # configuration: its inputs are those flake.lock pins. The checks read
  # the packages and the modules from it as a flake that lists
  # ch-emacs-config as an input reads them.
  chEmacsConfig = lib.caisson.callConsumerFlake {
    path = self.outPath;
    pool = inputs;
    sourceInfo = builtins.removeAttrs self.sourceInfo [ "dirty" ];
  };

in
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    { pkgs, system, ... }:
    let
      callConsumer =
        args:
        lib.caisson.callConsumerFlake (
          {
            pool = {
              inherit (inputs)
                caisson
                flake-parts
                home-manager
                nemacs
                nixpkgs
                ;
              parent = chEmacsConfig;
            };
          }
          // args
        );
      # merman: the mermaid renderer and language server, from the
      # merman-nix repository. The preview line: the language server and the mmdc
      # subcommand exist from 0.8.0 on, and 0.8.0 has only
      # prereleases so far.
      merman = inputs.merman-nix.packages.${system}.merman-preview;
      # The editors the caisson top publishes as its packages `emacs`
      # and `emacs-pgtk`.
      editor = chEmacsConfig.packages.${system}.emacs;
      editorPgtk = chEmacsConfig.packages.${system}.emacs-pgtk;
      markdownTableFixSrc = closure-lib.ch-emacs-config.packageSources.markdown-table-fix;
      renderDwimSrc = closure-lib.ch-emacs-config.packageSources.render-dwim;
      ghReviewSrc = closure-lib.ch-emacs-config.packageSources.gh-review;
      # The tests of the editor: elisp and scripts the checks below
      # run against a built Emacs, beside the other test trees.
      emacsTestsSrc = self.outPath + "/tests/emacs";
      # Batch-load the full init the way real startup does (package
      # activation fires the autoload hook).  load-init.el traps the
      # error-level warnings use-package demotes runtime errors to.
      mkInitLoadCheck =
        name: editor:
        pkgs.runCommand "${name}-init-load" { } ''
          export HOME="$TMPDIR"
          ${editor}/bin/emacs --batch -l ${emacsTestsSrc}/load-init.el
          touch $out
        '';
      # Boot a real daemon (early-init + full startup path, no frames)
      # and probe init health over emacsclient.  The probe expression
      # must stay free of single quotes for the shell quoting to hold.
      mkDaemonCheck =
        name: editor: emacsPackage:
        pkgs.runCommand "${name}-daemon-startup" { } ''
          export HOME="$TMPDIR/home"
          export XDG_RUNTIME_DIR="$TMPDIR/run"
          mkdir -p "$HOME"
          mkdir -p -m 700 "$XDG_RUNTIME_DIR"
          ${editor}/bin/emacs --daemon=smoke
          result="$(${emacsPackage}/bin/emacsclient -s smoke --eval \
            '(progn (load "${emacsTestsSrc}/daemon-probe.el") (ch-emacs-config-daemon-probe))')"
          ${emacsPackage}/bin/emacsclient -s smoke --eval '(kill-emacs 0)' 2>/dev/null || true
          echo "$result"
          [[ "$result" == '"OK"' ]]
          touch $out
        '';
      daemonInitSrc = closure-lib.ch-emacs-config.initFiles."daemon.el";
      # Rotation custody regression: a rotated daemon's exit must not
      # delete the canonical socket the new generation owns.  The exit
      # unlink happens through TWO paths: lisp server-stop (server-name)
      # and the C core (internal--daemon-sockname, an internal variable
      # we deliberately couple to in daemon.el's taint). This check
      # is the alarm that fires at build time if an Emacs bump renames
      # or rewires either path (field incident 2026-07-31).
      mkDrainCustodyCheck =
        name: emacsPackage:
        pkgs.runCommand "${name}-drain-custody" { } ''
          export HOME="$TMPDIR/home"
          export XDG_RUNTIME_DIR="$TMPDIR/run"
          mkdir -p "$HOME"
          mkdir -p -m 700 "$XDG_RUNTIME_DIR"
          sockdir="$XDG_RUNTIME_DIR/emacs"
          ${emacsPackage}/bin/emacs -Q -l ${daemonInitSrc} --daemon=server
          mv "$sockdir/server" "$sockdir/server-drain-test"
          ${emacsPackage}/bin/emacsclient --socket-name="$sockdir/server-drain-test" \
            --eval '(ch-emacs-config-daemon-taint "server-drain-test")'
          touch "$sockdir/server"
          ${emacsPackage}/bin/emacsclient --socket-name="$sockdir/server-drain-test" \
            --eval "(kill-emacs)" 2>/dev/null || true
          for _ in $(seq 100); do
            [[ -S "$sockdir/server-drain-test" ]] || break
            sleep 0.1
          done
          [[ ! -e "$sockdir/server-drain-test" ]]
          [[ -e "$sockdir/server" ]]
          touch $out
        '';
      # Last-frame gate: a tainted daemon asks before its last client
      # frame is deleted on every close path (direct `delete-frame',
      # the window-manager close event, C-x C-c on a nowait frame),
      # keeps the frame when declined, stays silent for a non-last
      # frame, and drains once the last frame is confirmed away.  The
      # gate is an advice on the `delete-frame' primitive reached from
      # native-compiled frame.el and server.el, so this also alarms if
      # an Emacs bump breaks advice on primitives for native callers.
      # Real tty client frames come from tests/pty-run.py.
      mkLastFrameGateCheck =
        name: emacsPackage:
        pkgs.runCommand "${name}-last-frame-gate" { nativeBuildInputs = [ pkgs.python3 ]; } ''
          export HOME="$TMPDIR/home"
          export XDG_RUNTIME_DIR="$TMPDIR/run"
          mkdir -p "$HOME"
          mkdir -p -m 700 "$XDG_RUNTIME_DIR"
          EMACS=${emacsPackage}/bin/emacs EMACSCLIENT=${emacsPackage}/bin/emacsclient \
            bash ${emacsTestsSrc}/daemon-last-frame-gate.sh ${daemonInitSrc}
          touch $out
        '';
      # The launchers of the daemon, with a stand-in for systemd that
      # records its calls and a stand-in for emacsclient that answers
      # `(emacs-pid)`, in a directory laid out as a Nix profile is: the
      # launchers and the editor binaries side by side.
      mkDaemonLaunchersCheck =
        let
          standIns = pkgs.symlinkJoin {
            name = "systemd-stand-in";
            paths = [
              (pkgs.writeShellScriptBin "systemctl" ''
                echo "systemctl $*" >> "$LOG"
                cat "$STATE_FILE"
              '')
              (pkgs.writeShellScriptBin "systemd-run" ''
                echo "systemd-run $*" >> "$LOG"
              '')
            ];
          };
          launchers = closure-lib.ch-emacs-config.mkDaemonLaunchers {
            inherit pkgs;
            systemd = standIns;
          };
        in
        pkgs.runCommand "daemon-launchers"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            export LOG="$TMPDIR/log"
            export XDG_RUNTIME_DIR="$TMPDIR/run"
            export STATE_FILE="$TMPDIR/state"
            mkdir -p -m 700 "$XDG_RUNTIME_DIR/emacs" "$TMPDIR/profile/bin"
            profile="$TMPDIR/profile/bin"
            sockdir="$XDG_RUNTIME_DIR/emacs"

            # The editor binaries resolve into the Nix store, as in a
            # profile, so the generation hash is the one of `hello`.
            ln -s ${pkgs.hello}/bin/hello "$profile/emacs"
            for program in ${launchers}/bin/*; do
              ln -s "$program" "$profile/$(basename "$program")"
            done
            gen=$(basename ${pkgs.hello} | cut -c1-12)

            cat > "$profile/emacsclient" <<'EOF'
            #!/bin/sh
            echo "emacsclient $*" >> "$LOG"
            case "$*" in
            *"(emacs-pid)"*) printf 4242 ;;
            esac
            EOF
            chmod +x "$profile/emacsclient"

            # An unmanaged socket: a unix socket file nothing listens on.
            mksock() { python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$1"; }

            # No daemon of this generation and none holding the socket:
            # the daemon starts, and the frame opens on the socket.
            : > "$LOG"; echo inactive > "$STATE_FILE"
            "$profile/emacsclient-desktop-launcher" a.txt
            grep -q "^systemd-run --user --quiet --collect --unit=emacs-daemon-$gen .*$profile/emacs --fg-daemon=server$" "$LOG"
            grep -q "^emacsclient --socket-name=$sockdir/server --create-frame --no-wait a.txt$" "$LOG"

            # The daemon of this generation runs: nothing starts.
            : > "$LOG"; echo active > "$STATE_FILE"
            "$profile/emacsclient-editor-launcher" b.txt
            ! grep -q '^systemd-run' "$LOG"
            grep -q "^emacsclient --socket-name=$sockdir/server b.txt$" "$LOG"

            # Another generation holds the socket: the socket moves to a
            # name of that daemon, the daemon is told it is replaced, and
            # the new daemon starts.
            mksock "$sockdir/server"
            : > "$LOG"; echo inactive > "$STATE_FILE"
            "$profile/emacsclient-desktop-launcher"
            test -S "$sockdir/server-drain-4242"
            test ! -e "$sockdir/server"
            grep -q "^emacsclient --socket-name=$sockdir/server-drain-4242 --eval (when (fboundp 'ch-emacs-config-daemon-taint) (ch-emacs-config-daemon-taint \"server-drain-4242\"))$" "$LOG"
            grep -q '^systemd-run .*--fg-daemon=server$' "$LOG"

            touch $out
          '';
      # An ERT suite run in batch by an editor, with extra load-path
      # entries or init steps before the test file.
      mkErtCheck =
        {
          name,
          editor,
          before,
          nativeBuildInputs ? [ ],
        }:
        pkgs.runCommand name { inherit nativeBuildInputs; } ''
          export HOME="$TMPDIR"
          ${editor}/bin/emacs --batch \
            ${before} \
            -l ${emacsTestsSrc}/${name}.el \
            -f ert-run-tests-batch-and-exit
          touch $out
        '';
    in
    {
      # Duplicated in the formatter partition of
      # configs/flake/ch-emacs-config: the partition and this
      # configuration are separate evaluations.
      treefmt.programs.nixfmt.enable = true;

      caisson.checks = {
        treefmt = {
          category = "format";
          description = "the Nix files are formatted with nixfmt";
        };

        # The unit tests, a caisson top in tests/unit, published as
        # `unit-<check>`.
        unit = {
          top = callConsumer { path = self.outPath + "/tests/unit"; };
          category = "unit";
        };

        # A caisson consumer that declares the editor inside a
        # home-manager configuration, published as
        # `caisson-consumer-<check>`.
        caisson-consumer = {
          top = callConsumer { path = self.outPath + "/tests/integration/caisson-consumer"; };
          category = "build";
          description = "a home-manager configuration that declares the editor as a nemacs configuration builds, and names the profile of the editor in the desktop entry, `$EDITOR`, `PATH` and fontconfig";
        };

        daemon-launchers = {
          derivation = mkDaemonLaunchersCheck;
          category = "unit";
          description = "the launchers start the daemon of their generation when it is not running, leave a running one alone, and retire the daemon that holds the socket before they start a newer one";
        };

        emacs-init-load = {
          derivation = mkInitLoadCheck "emacs" editor;
          category = "build";
          description = "the editor on the Emacs base package loads the full init in batch without error-level warnings";
        };
        emacs-pgtk-init-load = {
          derivation = mkInitLoadCheck "emacs-pgtk" editorPgtk;
          category = "build";
          description = "the editor on the pgtk Emacs base package loads the full init in batch without error-level warnings";
        };
        emacs-daemon-startup = {
          derivation = mkDaemonCheck "emacs" editor pkgs.ch-emacs-config.emacs;
          category = "build";
          description = "a daemon of the editor on the Emacs base package starts and its init reports healthy";
        };
        emacs-pgtk-daemon-startup = {
          derivation = mkDaemonCheck "emacs-pgtk" editorPgtk pkgs.ch-emacs-config.emacs-pgtk;
          category = "build";
          description = "a daemon of the editor on the pgtk Emacs base package starts and its init reports healthy";
        };
        emacs-drain-custody = {
          derivation = mkDrainCustodyCheck "emacs" pkgs.ch-emacs-config.emacs;
          category = "build";
          description = "a rotated daemon on the Emacs base package leaves the canonical socket of the new generation in place when it exits";
        };
        emacs-pgtk-drain-custody = {
          derivation = mkDrainCustodyCheck "emacs-pgtk" pkgs.ch-emacs-config.emacs-pgtk;
          category = "build";
          description = "a rotated daemon on the pgtk Emacs base package leaves the canonical socket of the new generation in place when it exits";
        };
        emacs-last-frame-gate = {
          derivation = mkLastFrameGateCheck "emacs" pkgs.ch-emacs-config.emacs;
          category = "build";
          description = "a tainted daemon on the Emacs base package asks before its last client frame is deleted, on every close path";
        };
        emacs-pgtk-last-frame-gate = {
          derivation = mkLastFrameGateCheck "emacs-pgtk" pkgs.ch-emacs-config.emacs-pgtk;
          category = "build";
          description = "a tainted daemon on the pgtk Emacs base package asks before its last client frame is deleted, on every close path";
        };
        # The test file activates packages to get it on the load path.
        markdown-table-fix-ert = {
          derivation = pkgs.runCommand "markdown-table-fix-ert" { } ''
            export HOME="$TMPDIR"
            ${editor}/bin/emacs --batch \
              -L ${markdownTableFixSrc} \
              -l tests/markdown-table-fix-ert.el \
              -f ert-run-tests-batch-and-exit
            touch $out
          '';
          category = "build";
          description = "the ERT suite of markdown-table-fix passes";
        };
        # Real ghostel and evil-ghostel are loaded, so an upstream
        # rename or arity change fails here instead of at runtime.
        ch-evil-ghostel-ert = {
          derivation = mkErtCheck {
            name = "ch-evil-ghostel-ert";
            inherit editor;
            before = "-f package-activate-all";
          };
          category = "build";
          description = "the six behaviors ch-evil-ghostel layers on evil-ghostel call the ghostel functions they should, with the arguments they should";
        };
        # The init loads consult-ghostel only after both ghostel and
        # consult, which the init-load check never loads.
        consult-ghostel-ert = {
          derivation = mkErtCheck {
            name = "consult-ghostel-ert";
            inherit editor;
            before = "-l ${emacsTestsSrc}/load-init.el";
          };
          category = "build";
          description = "with the full init loaded, the consult-ghostel mode comes on and the leader keys land where they should";
        };
        # A token-reading regression there is silent, since the tree
        # still renders and only the commands stop finding anything.
        speedbar-project-ert = {
          derivation = mkErtCheck {
            name = "speedbar-project-ert";
            inherit editor;
            before = "-l ${emacsTestsSrc}/load-init.el";
          };
          category = "build";
          description = "with the full init loaded, the delete commands of the speedbar Project tree find the entries they act on";
        };
        # The functions read buffer-local state and return strings, so
        # --batch exercises them as redisplay does.
        mode-line-ert = {
          derivation = mkErtCheck {
            name = "mode-line-ert";
            inherit editor;
            before = "-f package-activate-all";
          };
          category = "build";
          description = "a saved, writable, local, UTF-8 buffer contributes no characters to the left edge of the mode line";
        };
        render-dwim-ert = {
          derivation = mkErtCheck {
            name = "render-dwim-ert";
            inherit editor;
            before = "-L ${renderDwimSrc}";
            nativeBuildInputs = [ merman ];
          };
          category = "build";
          description = "render-dwim extracts and normalizes diagrams and renders and detects them end to end, with merman on PATH";
        };
        gh-review-ert = {
          derivation = mkErtCheck {
            name = "gh-review-ert";
            inherit editor;
            before = "-L ${ghReviewSrc}";
            nativeBuildInputs = [ pkgs.git ];
          };
          category = "build";
          description = "gh-review parses diffs, plans context lines, renders, and fetches and diffs against a local repository standing in for GitHub";
        };
        jinx-merge-personal-dict = {
          derivation =
            let
              merge = closure-lib.ch-emacs-config.mkJinxMergePersonalDict {
                inherit pkgs;
              };
            in
            pkgs.runCommand "jinx-merge-personal-dict-check" { } ''
              merge=${lib.getExe merge}
              printf '%s\n' alpha beta gamma > declared

              # fresh: no dictionary yet, parent dir created
              "$merge" declared fresh/en_US.dic
              printf '%s\n' alpha beta gamma > expected
              diff -u expected fresh/en_US.dic

              # merge: runtime-saved words kept in place, only missing appended
              printf '%s\n' runtime beta > merged.dic
              "$merge" declared merged.dic
              printf '%s\n' runtime beta alpha gamma > expected
              diff -u expected merged.dic

              # idempotent: a second run must not change the file
              cp merged.dic before.dic
              "$merge" declared merged.dic
              diff -u before.dic merged.dic

              # missing trailing newline is repaired, words cannot fuse
              printf 'runtime' > ragged.dic
              "$merge" declared ragged.dic
              printf '%s\n' runtime alpha beta gamma > expected
              diff -u expected ragged.dic

              # blanks and duplicates inside the declared list are dropped
              printf '%s\n' alpha "" alpha delta > messy-declared
              : > empty.dic
              "$merge" messy-declared empty.dic
              printf '%s\n' alpha delta > expected
              diff -u expected empty.dic

              touch $out
            '';
          category = "build";
          description = "the merge of the personal dictionary creates, appends without duplicates, is idempotent, repairs a missing trailing newline and drops blanks";
        };
      };
    };
}
