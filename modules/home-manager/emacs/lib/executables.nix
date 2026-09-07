# SPDX-License-Identifier: MIT
#
# The external programs the init spawns by name, and the init lines that
# pin each one to a store path. The language servers keep their own
# table (../../lib/language-servers.nix); `initContent` renders that
# table's eglot wiring too, so one call yields every pin the init needs
# and the Home Manager module and the exported package cannot drift.
#
# Each entry is a package or null. A package is closed over: the init
# sets the variable the consuming package reads its program from, after
# that package loads, so the package's own bare-name default never wins.
# consult-gh is the exception: it looks up a bare "gh" it does not let
# you configure, so its bin directory goes on `exec-path' instead. Null
# leaves the program to PATH at run time; the README lists what a host
# must then provide.
#
# Programs any Linux host carries (a POSIX userland, man, the login
# shell ghostel spawns) are not pinned: a store-pinned `man' would not
# know the host's page directories, and the shell is the user's.
{ lib, pkgs }:
let
  elispString = s: ''"${s}"'';

  # Render an argv as elisp string literals.
  elispStrings = lib.concatMapStringsSep " " elispString;

  # Render a language server's workspace settings as an eglot plist:
  # attrsets become plists, lists become vectors (JSON arrays),
  # everything else is a string. The table's settings hold nothing but
  # those shapes.
  toElispPlist =
    v:
    if lib.isAttrs v then
      "(" + lib.concatStringsSep " " (lib.mapAttrsToList (k: v': ":${k} ${toElispPlist v'}") v) + ")"
    else if lib.isList v then
      "[" + lib.concatMapStringsSep " " toElispPlist v + "]"
    else
      elispString v;

  # A variable set once the file defining it has loaded. The `defvar'
  # keeps the byte compiler (which runs with `byte-compile-error-on-warn')
  # from reporting an assignment to a free variable.
  setAfterLoad = feature: variable: value: ''
    (defvar ${variable})
    (with-eval-after-load '${feature}
      (setq ${variable} ${value}))
  '';
in
{
  # One entry per program: its default package, and what in the init
  # spawns it. merman is not in nixpkgs, so it has no default here: the
  # Home Manager module takes it from this flake's input, and a
  # package-scope caller passes it, or leaves the mermaid tooling to
  # PATH.
  table = {
    git = {
      default = pkgs.git;
      defaultText = "pkgs.git";
      description = "git, for magit and the built-in vc backend (diff-hl, project).";
    };
    ripgrep = {
      default = pkgs.ripgrep;
      defaultText = "pkgs.ripgrep";
      description = "ripgrep, the project grep behind consult-ripgrep.";
    };
    direnv = {
      default = pkgs.direnv;
      defaultText = "pkgs.direnv";
      description = "direnv, for envrc.";
    };
    gh = {
      default = pkgs.gh;
      defaultText = "pkgs.gh";
      description = "The GitHub CLI, for consult-gh.";
    };
    plantuml = {
      default = pkgs.plantuml;
      defaultText = "pkgs.plantuml";
      description = "plantuml, for plantuml-mode previews and render-dwim.";
    };
    graphviz = {
      default = pkgs.graphviz;
      defaultText = "pkgs.graphviz";
      description = "graphviz, whose dot renders graphviz blocks in render-dwim.";
    };
    merman = {
      default = null;
      defaultText = "null";
      description = ''
        merman, the headless mermaid renderer behind mermaid-preview and
        render-dwim, and the mermaid language server in the shared server
        table. Not in nixpkgs: github:clhodapp/merman exports it.
      '';
    };
  };

  # The pins for EXECUTABLES (an attrset shaped like `table`, values
  # packages or null) under BUNDLES (the resolved bundle set: the pins
  # for a feature are emitted only when its bundle is enabled).
  initContent =
    { executables, bundles }:
    let
      on = name: bundles.${name}.enable or false;
      pinned = name: executables.${name} or null != null;
      exe = name: executables.${name};

      languageServers = import ../../lib/language-servers.nix pkgs {
        merman = executables.merman or null;
      };
      lspWorkspaceSettings = lib.foldl' lib.recursiveUpdate { } (
        map (s: s.settings or { }) (lib.attrValues languageServers)
      );

      merman = executables.merman or null;
      mermanCommand = sub: "(list ${elispString (lib.getExe merman)} ${elispString sub})";

      sections = lib.concatStrings [
        (lib.optionalString (pinned "git") (
          setAfterLoad "vc-git" "vc-git-program" (elispString "${exe "git"}/bin/git")
          + lib.optionalString (on "magit") (
            setAfterLoad "magit-git" "magit-git-executable" (elispString "${exe "git"}/bin/git")
          )
        ))
        (lib.optionalString (pinned "ripgrep" && on "vertico") ''
          ;; consult's argument string opens with the program; only that
          ;; word is replaced, so upstream's flags stay upstream's.
          (defvar consult-ripgrep-args)
          (with-eval-after-load 'consult
            (setq consult-ripgrep-args
                  (if (stringp consult-ripgrep-args)
                      (replace-regexp-in-string "\\`[^ ]+" ${elispString "${exe "ripgrep"}/bin/rg"}
                                                consult-ripgrep-args t t)
                    (cons ${elispString "${exe "ripgrep"}/bin/rg"} (cdr consult-ripgrep-args)))))
        '')
        (lib.optionalString (pinned "direnv" && on "envrc") (
          setAfterLoad "envrc" "envrc-direnv-executable" (elispString "${exe "direnv"}/bin/direnv")
        ))
        (lib.optionalString (pinned "gh" && on "consult-gh") ''
          ;; consult-gh spawns a bare "gh" and checks for it by that name,
          ;; so the pin is a directory on `exec-path', ahead of the host's.
          (add-to-list 'exec-path ${elispString "${exe "gh"}/bin"})
        '')
        (lib.optionalString (pinned "plantuml" && on "plantuml-mode") (
          setAfterLoad "plantuml-mode" "plantuml-executable-path" (
            elispString "${exe "plantuml"}/bin/plantuml"
          )
        ))
        (lib.optionalString (on "render-dwim") (
          lib.optionalString (pinned "plantuml") (
            setAfterLoad "render-dwim" "render-dwim-plantuml-command"
              "(list ${elispString "${exe "plantuml"}/bin/plantuml"})"
          )
          + lib.optionalString (pinned "graphviz") (
            setAfterLoad "render-dwim" "render-dwim-dot-command"
              "(list ${elispString "${exe "graphviz"}/bin/dot"})"
          )
          + lib.optionalString (pinned "merman") (
            setAfterLoad "render-dwim" "render-dwim-mermaid-command" (mermanCommand "mmdc")
            + setAfterLoad "render-dwim" "render-dwim-detect-command" (mermanCommand "detect")
          )
        ))
        (lib.optionalString (pinned "merman" && on "mermaid-ts-mode") (
          setAfterLoad "mermaid-preview" "mermaid-preview-command" (mermanCommand "mmdc")
        ))
        (lib.optionalString (on "eglot") ''
          ;; Language servers from the shared table (../../lib/language-servers.nix),
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
          ${
            lib.optionalString (languageServers ? merman-lsp) (
              "  (add-to-list 'eglot-server-programs\n"
              + "               '(mermaid-ts-mode . (${elispStrings languageServers.merman-lsp.cmd})))\n"
            )
          }  (add-to-list 'eglot-server-programs
                         '(bash-ts-mode . (${elispStrings languageServers.bash-language-server.cmd}))))
          (setq-default eglot-workspace-configuration
                        '${toElispPlist lspWorkspaceSettings})
        '')
      ];
    in
    lib.optionalString (sections != "") ''
      ;; Programs the init spawns, pinned to store paths
      ;; (modules/home-manager/emacs/lib/executables.nix). Each variable
      ;; is set once its package has loaded, so the package's bare-name
      ;; default never wins.
      ${sections}
    '';
}
