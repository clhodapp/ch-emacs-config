# SPDX-License-Identifier: MIT
#
# The bundles this configuration defines: what each turns on, the init
# it contributes, and the packages that init needs. Every bundle is on
# by default (`lib.mkDefault`), so a plain `enable = false` elsewhere
# turns one off. The `emacs` bundle is the baseline the others assume,
# so it comes first; the rest follow in name order.
{ lib, initFiles }:
let
  readInit = name: builtins.readFile initFiles.${name};

  treesitGrammars =
    epkgs:
    epkgs.treesit-grammars.with-grammars (g: [
      g.tree-sitter-bash
      g.tree-sitter-java
      g.tree-sitter-javascript
      g.tree-sitter-json
      g.tree-sitter-markdown
      g.tree-sitter-markdown-inline
      g.tree-sitter-mermaid
      g.tree-sitter-nix
      g.tree-sitter-python
      g.tree-sitter-ruby
      g.tree-sitter-rust
      g.tree-sitter-toml
      g.tree-sitter-tsx
      g.tree-sitter-typescript
      g.tree-sitter-yaml
    ]);

  bundles = {
    daemon = {
      init = readInit "daemon.el";
    };

    embark = {
      init = readInit "embark.el";
      packages = epkgs: [
        epkgs.embark
        epkgs.embark-consult
      ];
    };

    corfu = {
      init = readInit "corfu.el";
      packages = epkgs: [
        epkgs.corfu
        epkgs.cape
      ];
    };

    consult-gh = {
      init = readInit "consult-gh.el";
      packages = epkgs: [
        epkgs.consult-gh
        epkgs.consult-gh-embark
        epkgs.consult-gh-with-pr-review
      ];
    };

    csv-mode = {
      init = readInit "csv-mode.el";
      packages = epkgs: [ epkgs.csv-mode ];
    };

    dired = {
      init = readInit "dired.el";
    };

    emacs = {
      order = 200;
      init = readInit "emacs.el";
      packages = epkgs: [
        epkgs.color-theme-sanityinc-tomorrow
        (treesitGrammars epkgs)
      ];
    };

    diff-hl = {
      init = readInit "diff-hl.el";
      packages = epkgs: [ epkgs.diff-hl ];
    };

    eglot = {
      init = readInit "eglot.el";
      packages = epkgs: [ epkgs.consult-eglot ];
    };

    envrc = {
      init = readInit "envrc.el";
      packages = epkgs: [ epkgs.envrc ];
    };

    evil = {
      init = readInit "evil.el";
      packages = epkgs: [
        epkgs.evil
        epkgs.evil-collection
        epkgs.evil-commentary
      ];
    };

    vertico = {
      init = readInit "vertico.el";
      packages = epkgs: [
        epkgs.vertico
        epkgs.orderless
        epkgs.marginalia
        epkgs.consult
        epkgs.wgrep
      ];
    };

    indent-bars = {
      init = readInit "indent-bars.el";
      packages = epkgs: [ epkgs.indent-bars ];
    };

    jinx = {
      init = readInit "jinx.el";
      packages = epkgs: [ epkgs.jinx ];
    };

    nerd-icons = {
      init = readInit "nerd-icons.el";
      packages = epkgs: [
        epkgs.nerd-icons
        epkgs.nerd-icons-completion
        epkgs.nerd-icons-corfu
        epkgs.nerd-icons-dired
      ];
    };

    nix-ts-mode = {
      init = readInit "nix-ts-mode.el";
      packages = epkgs: [ epkgs.nix-ts-mode ];
    };

    plantuml-mode = {
      init = readInit "plantuml-mode.el";
      packages = epkgs: [ epkgs.plantuml-mode ];
    };

    pr-review = {
      init = readInit "pr-review.el";
      packages = epkgs: [ epkgs.pr-review ];
    };

    gh-review = {
      init = readInit "gh-review.el";
      packages = epkgs: [ epkgs.gh-review ];
    };

    project = {
      init = readInit "project.el";
    };

    scroll-bar = {
      init = readInit "scroll-bar.el";
    };

    help = {
      init = readInit "help.el";
    };

    man = {
      init = readInit "man.el";
    };

    tool-bar = {
      init = readInit "tool-bar.el";
    };

    mouse = {
      init = readInit "mouse.el";
    };

    mode-line = {
      init = readInit "mode-line.el";
    };

    magit = {
      init = readInit "magit.el";
      packages = epkgs: [ epkgs.magit ];
    };

    markdown-ts-mode = {
      init = readInit "markdown-ts-mode.el";
      # Emacs 31 ships `markdown-ts-mode` built in (same feature name and
      # `markdown-ts-mode-map`), and the ELPA package refuses to load
      # beside it, so it is only installed for older Emacsen.
      packages =
        epkgs:
        (if builtins.compareVersions epkgs.emacs.version "31" < 0 then [ epkgs.markdown-ts-mode ] else [ ])
        ++ [ epkgs.markdown-table-fix ];
    };

    mermaid-ts-mode = {
      init = readInit "mermaid-ts-mode.el";
      packages = epkgs: [
        epkgs.mermaid-ts-mode
        epkgs.mermaid-preview
      ];
    };

    render-dwim = {
      init = readInit "render-dwim.el";
      packages = epkgs: [ epkgs.render-dwim ];
    };

    ghostel = {
      init = readInit "ghostel.el";
      # evil-ghostel is listed alongside the core even though
      # ch-evil-ghostel already pulls it in, so the package manifest
      # records the version it was built at: it comes from ghostel's own
      # source tree via an overlay, not from emacs-overlay's package set.
      # consult-ghostel comes from the same tree.
      packages = epkgs: [
        epkgs.ghostel
        epkgs.evil-ghostel
        epkgs.consult-ghostel
        epkgs.ch-evil-ghostel
        epkgs.ghostel-funcs
      ];
    };

    speedbar = {
      init = readInit "speedbar.el";
      # nerd-icons supplies the PR tree's file/directory glyphs; listed
      # here so the bundle stands alone if the nerd-icons bundle is off.
      packages = epkgs: [ epkgs.nerd-icons ];
    };

    treesit-fold = {
      init = readInit "treesit-fold.el";
      packages = epkgs: [ epkgs.treesit-fold ];
    };

    rust-ts-mode = {
      init = readInit "rust-ts-mode.el";
    };

    typescript-ts-mode = {
      init = readInit "typescript-ts-mode.el";
    };

    vundo = {
      init = readInit "vundo.el";
      packages = epkgs: [ epkgs.vundo ];
    };

    which-key = {
      init = readInit "which-key.el";
    };

    window-funcs = {
      init = readInit "window-funcs.el";
      packages = epkgs: [ epkgs.window-funcs ];
    };
  };
in
lib.mapAttrs (_name: bundle: bundle // { enable = lib.mkDefault true; }) bundles
