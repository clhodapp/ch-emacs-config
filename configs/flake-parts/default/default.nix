# SPDX-License-Identifier: MIT
{ closure-lib, ... }:
{
  inputs,
  lib,
  ...
}:
{

  debug = false;
  systems = [ "x86_64-linux" ];

  caisson.nixpkgs.overlays = {
    all = {
      # `pkgs.ch-emacs-config.emacs`, `.emacs-pgtk`, `.emacs-nox`: the Emacs
      # base packages the configuration is validated against
      # (pkgs/ch-emacs-config/emacs-base.nix picks the newest supported
      # major nixpkgs carries as a final release).
      emacs = closure-lib.caisson.nixpkgs.mkPackagesOverlay ../../../pkgs/ch-emacs-config;
      # `pkgs.merman.merman`: the headless mermaid renderer behind
      # render-dwim and mermaid-preview, and the mermaid language
      # server the shared table spawns.
      merman = _name: inputs.merman.overlays.packages;
      # MELPA/ELPA package pins only; does not add emacs-git or other
      # tip-of-tree emacsen.
      emacs-packages = _: inputs.emacs-overlay.overlays.package;
    };
    export.enabled = true;
    exported = overlays: { inherit (overlays) emacs emacs-packages; };
  };

  caisson.configInfo.configName = "ch-emacs-config";
  caisson.modules = {
    flake.exported = modules: { inherit (modules) default emacs; };
    homeManager.exported = modules: { inherit (modules) emacs; };
  };

  # What an agent needs to talk to a live Emacs: two hook scripts and a
  # skill describing the MCP server's tools. Exported as an interface so
  # a consumer names these rather than a path into this tree, which
  # would make the directory layout the contract and break silently when
  # a file moves. This flake still knows nothing about any particular
  # agent: it publishes what it has, and the wiring lives with whoever
  # registers hooks.
  flake.agentIntegration = {
    cwdHookScript = ../../../modules/home-manager/emacs/lib/emacs-claude-cwd-hook.sh;
    consentHookScript = ../../../modules/home-manager/emacs/lib/emacs-claude-consent-hook.sh;
    toolsSkill = ../../../modules/home-manager/emacs/skills/emacs-tools;
  };

  partitionedAttrs.checks = "checks";
  # packages are built from the same emacs-overlay nixpkgs as the checks
  # that validate them; no independent pin is possible without duplicating
  # the shared let setup, so they share the checks partition.
  partitionedAttrs.packages = "checks";
  partitionedAttrs.formatter = "formatter";

  partitions.formatter = {
    extraInputs = lib.caisson-core.partitionExtraInputs ../../../tests/dependencies;
    module =
      { inputs, ... }:
      {
        imports = [ inputs.treefmt-nix.flakeModule ];
        # treefmt reads the perSystem `pkgs`, which caisson's nixpkgs
        # module supplies from this package set.
        caisson.nixpkgs.pkgSets.pkgs.pkgFunction = import inputs.nixpkgs;
        perSystem.treefmt.programs.nixfmt.enable = true;
      };
  };

  partitions.checks = {
    extraInputs = lib.caisson-core.partitionExtraInputs ../../../tests/dependencies;
    module =
      { inputs, self, ... }:
      {
        imports = [ inputs.treefmt-nix.flakeModule ];
        # The package set the checks build against: the ELPA pins and the
        # Emacs base selection, in the order consumers are told to apply
        # them. The checks then validate exactly what the overlays
        # propose.
        caisson.nixpkgs.pkgSets.pkgs = {
          pkgFunction = import inputs.nixpkgs;
          overlayImports = overlays: [
            overlays.emacs-packages
            overlays.emacs
            overlays.merman
          ];
        };
        perSystem =
          { pkgs, system, ... }:
          let
            consumerPool = {
              inherit (inputs) caisson home-manager nixpkgs;
              parent = self;
            };
            callConsumer =
              args:
              closure-lib.caisson-core.callConsumerFlake (
                {
                  pool = consumerPool;
                }
                // args
              );
            unitOutputs = callConsumer {
              path = self.outPath + "/tests/unit";
            };
            # The README's plain-flake recipe (no flake-parts, no
            # framework), held as a check.
            plainConsumerOutputs = callConsumer {
              path = self.outPath + "/tests/integration/plain-consumer";
            };
            emacsBundleSpec = import ../../../modules/home-manager/emacs/bundles/spec.nix;
            # Packages consumed as plain (non-flake) inputs; see pkgs/emacs/overrides.nix.
            emacsPackageSources = {
              inherit (inputs) collab-comments parenting pr-review;
            };
            mkEmacsDefault =
              emacsPackage:
              import ../../../modules/home-manager/emacs/lib/package-scope.nix {
                inherit pkgs emacsPackage;
                lib = pkgs.lib;
                bundles = emacsBundleSpec;
                sources = emacsPackageSources;
              };
            emacsScope = mkEmacsDefault pkgs.ch-emacs-config.emacs;
            emacsPgtkScope = mkEmacsDefault pkgs.ch-emacs-config.emacs-pgtk;
            emacsOverlayRev = inputs.emacs-overlay.rev or inputs.emacs-overlay.sourceInfo.rev or null;
            emacsPackageManifest = pkgs.callPackage ../../../pkgs/emacs/manifest-package.nix {
              emacsPackage = pkgs.ch-emacs-config.emacs;
              bundles = emacsBundleSpec;
              sources = emacsPackageSources;
              inherit emacsOverlayRev;
            };
            # merman: the mermaid renderer and language server, its own repo.
            merman = inputs.merman.packages.${system}.merman;
            aiCommitSrc = "${self}/modules/home-manager/emacs/packages/ai-commit";
            claudeQueueSrc = "${self}/modules/home-manager/emacs/packages/claude-queue";
            markdownTableFixSrc = "${self}/modules/home-manager/emacs/packages/markdown-table-fix";
            renderDwimSrc = "${self}/modules/home-manager/emacs/packages/render-dwim";
            semanticFinderSrc = "${self}/modules/home-manager/emacs/packages/semantic-finder";
            emacsTestsSrc = "${self}/modules/home-manager/emacs/tests";
            # Batch-load the full init the way real startup does (package
            # activation fires the autoload hook).  load-init.el traps the
            # error-level warnings use-package demotes runtime errors to.
            mkInitLoadCheck =
              name: scope:
              pkgs.runCommand "${name}-init-load" { } ''
                export HOME="$TMPDIR"
                ${scope.emacs}/bin/emacs --batch -l ${emacsTestsSrc}/load-init.el
                touch $out
              '';
            # Boot a real daemon (early-init + full startup path, no frames)
            # and probe init health over emacsclient.  The probe expression
            # must stay free of single quotes for the shell quoting to hold.
            mkDaemonCheck =
              name: scope: emacsPackage:
              pkgs.runCommand "${name}-daemon-startup" { } ''
                export HOME="$TMPDIR/home"
                export XDG_RUNTIME_DIR="$TMPDIR/run"
                mkdir -p "$HOME"
                mkdir -p -m 700 "$XDG_RUNTIME_DIR"
                ${scope.emacs}/bin/emacs --daemon=smoke
                result="$(${emacsPackage}/bin/emacsclient -s smoke --eval \
                  '(progn (load "${emacsTestsSrc}/daemon-probe.el") (ch-emacs-config-daemon-probe))')"
                ${emacsPackage}/bin/emacsclient -s smoke --eval '(kill-emacs 0)' 2>/dev/null || true
                echo "$result"
                [[ "$result" == '"OK"' ]]
                touch $out
              '';
            daemonInitSrc = "${self}/modules/home-manager/emacs/inits/daemon.el";
            # Rotation custody regression: a rotated daemon's exit must not
            # delete the canonical socket the new generation owns.  The exit
            # unlink happens through TWO paths — lisp server-stop (server-name)
            # and the C core (internal--daemon-sockname, an internal variable
            # we deliberately couple to in daemon.el's taint) — so this check
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
            # Bare-name mmdc for the ERT run, so the present tool's
            # mermaid tests exercise the renderer instead of skipping
            # (the init's default command is ("mmdc")).
            mermanMmdcShim = pkgs.writeShellScriptBin "mmdc" ''exec ${lib.getExe merman} mmdc "$@"'';
            # Evaluate the home-manager module end to end: option types, the
            # programs.emacs wiring, bundle-conditional home.packages, and
            # the mcp stdio bridge all get forced by the activation package.
            #
            # The module also contributes a skill and hooks to an agent
            # module's options when one is present. That wiring is
            # deliberately not exercised here: this flake knows nothing
            # about the agent side, and the check that both halves compose
            # belongs to whichever repo imports both.
            emacsHomeManagerConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                self.modules.homeManager.emacs
                {
                  home.username = "tester";
                  home.homeDirectory = "/home/tester";
                  home.stateVersion = "25.05";
                  # `package` is left at its default so the check covers
                  # the overlay-backed selection.
                  ch-emacs-config.emacs = {
                    enable = true;
                    # Forces the jinx personal-dictionary option type and
                    # the merge activation entry through evaluation.
                    jinxPersonalWords = [ "hmcheckword" ];
                  };
                }
              ];
            };
          in
          {
            checks =
              unitOutputs.checks.${system}
              // plainConsumerOutputs.checks.${system}
              // {
                emacs = emacsScope.emacs;
                emacs-pgtk = emacsPgtkScope.emacs;
                emacs-init-load = mkInitLoadCheck "emacs" emacsScope;
                emacs-pgtk-init-load = mkInitLoadCheck "emacs-pgtk" emacsPgtkScope;
                emacs-daemon-startup = mkDaemonCheck "emacs" emacsScope pkgs.ch-emacs-config.emacs;
                emacs-pgtk-daemon-startup =
                  mkDaemonCheck "emacs-pgtk" emacsPgtkScope
                    pkgs.ch-emacs-config.emacs-pgtk;
                emacs-drain-custody = mkDrainCustodyCheck "emacs" pkgs.ch-emacs-config.emacs;
                emacs-pgtk-drain-custody = mkDrainCustodyCheck "emacs-pgtk" pkgs.ch-emacs-config.emacs-pgtk;
                emacs-home-manager-module = emacsHomeManagerConfiguration.activationPackage;
                # The tic-check Stop hook with the seeded table against
                # synthetic payloads.  First stop: a block headed
                # "tic-check: check" naming each matched entry and count and
                # both verdict lines on a hit (whole words only, "yourself"
                # excluded; the em-dash and "click" entries fire on prose),
                # silence when the only matches sit inside a code fence or
                # backtick span, on a clean message, on a payload without
                # the field, and on non-JSON stdin.  Second stop
                # (stop_hook_active): a block headed "tic-check: rewrite" on
                # the "tic" verdict only; silence on the clean verdict and
                # on a regenerated message.
                ai-commit-ert = pkgs.runCommand "ai-commit-ert" { } ''
                  ${emacsPgtkScope.emacs}/bin/emacs --batch \
                    -L ${aiCommitSrc} \
                    -l tests/ai-commit-ert.el \
                    -f ert-run-tests-batch-and-exit
                  touch $out
                '';
                # The semantic finder's server-free surface: slicing,
                # staleness, response parsing, ranking, and the stale-OK
                # on-demand indexing policy (requests mocked).
                semantic-finder-ert = pkgs.runCommand "semantic-finder-ert" { } ''
                  export HOME="$TMPDIR"
                  ${emacsPgtkScope.emacs}/bin/emacs --batch \
                    -L ${semanticFinderSrc} \
                    -l tests/semantic-finder-ert.el \
                    -f ert-run-tests-batch-and-exit
                  touch $out
                '';
                # claude-queue requires semantic-finder (the agent finder
                # ranks transcripts through its embedding client).
                claude-queue-ert = pkgs.runCommand "claude-queue-ert" { } ''
                  export HOME="$TMPDIR"
                  ${emacsPgtkScope.emacs}/bin/emacs --batch \
                    -L ${claudeQueueSrc} \
                    -L ${semanticFinderSrc} \
                    -l tests/claude-queue-ert.el \
                    -f ert-run-tests-batch-and-exit
                  touch $out
                '';
                # The consent spool's Emacs half (same package directory
                # as claude-queue): layout, territory records, dead-pid
                # pruning, answer delivery, rendering.  The hook half is
                # bash, exercised live against the CLI, not here.
                claude-consent-ert = pkgs.runCommand "claude-consent-ert" { } ''
                  export HOME="$TMPDIR"
                  ${emacsPgtkScope.emacs}/bin/emacs --batch \
                    -L ${claudeQueueSrc} \
                    -l tests/claude-consent-ert.el \
                    -f ert-run-tests-batch-and-exit
                  touch $out
                '';
                # The scope emacs (not a bare one) supplies the markdown
                # tree-sitter grammar the fixer parses tables with; the
                # test file activates packages to get it on the load path.
                markdown-table-fix-ert = pkgs.runCommand "markdown-table-fix-ert" { } ''
                  export HOME="$TMPDIR"
                  ${emacsScope.emacs}/bin/emacs --batch \
                    -L ${markdownTableFixSrc} \
                    -l tests/markdown-table-fix-ert.el \
                    -f ert-run-tests-batch-and-exit
                  touch $out
                '';
                # MCP agent tools against the full init: registration (which
                # validates the tool docstring schemas), the non-LSP tools end
                # to end, and clean tool errors from the LSP-backed ones.
                emacs-mcp-tools-ert =
                  pkgs.runCommand "emacs-mcp-tools-ert"
                    {
                      # The mermaid tests skip without an mmdc on PATH;
                      # the shim makes them exercise the real renderer.
                      nativeBuildInputs = [ mermanMmdcShim ];
                    }
                    ''
                      export HOME="$TMPDIR"
                      ${emacsScope.emacs}/bin/emacs --batch \
                        -l ${emacsTestsSrc}/mcp-tools-ert.el \
                        -f ert-run-tests-batch-and-exit
                      touch $out
                    '';
                # render-dwim's extraction and normalization, plus the
                # render and detect paths end to end (merman on PATH).
                render-dwim-ert =
                  pkgs.runCommand "render-dwim-ert"
                    {
                      nativeBuildInputs = [ merman ];
                    }
                    ''
                      export HOME="$TMPDIR"
                      ${emacsScope.emacs}/bin/emacs --batch \
                        -L ${renderDwimSrc} \
                        -l ${emacsTestsSrc}/render-dwim-ert.el \
                        -f ert-run-tests-batch-and-exit
                      touch $out
                    '';
                # The collab-comments integration: the add-comment/list-comments
                # MCP tools with their edit-contract anchor matching, and threads
                # surviving present and transcript re-renders.  The package's own
                # suite runs in its repository (github:clhodapp/collab-comments).
                emacs-collab-comments-ert = pkgs.runCommand "emacs-collab-comments-ert" { } ''
                  export HOME="$TMPDIR"
                  ${emacsScope.emacs}/bin/emacs --batch \
                    -l ${emacsTestsSrc}/collab-comments-ert.el \
                    -f ert-run-tests-batch-and-exit
                  touch $out
                '';
                # Behavioral contract of the personal-dictionary merge: fresh
                # creation, append-only dedup against runtime-saved words,
                # idempotence, trailing-newline repair, declared-list hygiene.
                jinx-merge-personal-dict =
                  let
                    merge = import ../../../modules/home-manager/emacs/lib/jinx-merge-personal-dict.nix {
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
              };
            packages = {
              inherit (emacsScope) emacs;
              emacs-pgtk = emacsPgtkScope.emacs;
              emacs-package-manifest = emacsPackageManifest;
            };
            treefmt.programs.nixfmt.enable = true;
          };
      };
  };

}
