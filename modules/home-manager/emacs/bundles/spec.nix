# SPDX-License-Identifier: MIT
let
  readInit = name: builtins.readFile ../inits/${name};

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
      g.tree-sitter-toml
      g.tree-sitter-tsx
      g.tree-sitter-typescript
      g.tree-sitter-yaml
    ]);
in
{
  daemon = {
    enable = true;
    init = readInit "daemon.el";
    packages = _epkgs: _: [ ];
  };

  embark = {
    enable = true;
    init = readInit "embark.el";
    packages = epkgs: _: [
      epkgs.embark
      epkgs.embark-consult
    ];
  };

  corfu = {
    enable = true;
    init = readInit "corfu.el";
    packages = epkgs: _: [
      epkgs.corfu
      epkgs.cape
    ];
  };

  consult-gh = {
    enable = true;
    init = readInit "consult-gh.el";
    packages = epkgs: _: [
      epkgs.consult-gh
      epkgs.consult-gh-embark
      epkgs.consult-gh-with-pr-review
    ];
  };

  csv-mode = {
    enable = true;
    init = readInit "csv-mode.el";
    packages = epkgs: _: [ epkgs.csv-mode ];
  };

  dired = {
    enable = true;
    init = readInit "dired.el";
    packages = _epkgs: _: [ ];
  };

  emacs = {
    enable = true;
    init = readInit "emacs.el";
    packages = epkgs: _: [
      epkgs.color-theme-sanityinc-tomorrow
      (treesitGrammars epkgs)
    ];
  };

  diff-hl = {
    enable = true;
    init = readInit "diff-hl.el";
    packages = epkgs: _: [ epkgs.diff-hl ];
  };

  eglot = {
    enable = true;
    init = readInit "eglot.el";
    packages = epkgs: _: [ epkgs.consult-eglot ];
  };

  envrc = {
    enable = true;
    init = readInit "envrc.el";
    packages = epkgs: _: [ epkgs.envrc ];
  };

  evil = {
    enable = true;
    init = readInit "evil.el";
    packages = epkgs: _: [
      epkgs.evil
      epkgs.evil-collection
      epkgs.evil-commentary
    ];
  };

  vertico = {
    enable = true;
    init = readInit "vertico.el";
    packages = epkgs: _: [
      epkgs.vertico
      epkgs.orderless
      epkgs.marginalia
      epkgs.consult
      epkgs.wgrep
    ];
  };

  indent-bars = {
    enable = true;
    init = readInit "indent-bars.el";
    packages = epkgs: _: [ epkgs.indent-bars ];
  };

  jinx = {
    enable = true;
    init = readInit "jinx.el";
    packages = epkgs: _: [ epkgs.jinx ];
  };

  nerd-icons = {
    enable = true;
    init = readInit "nerd-icons.el";
    packages = epkgs: _: [
      epkgs.nerd-icons
      epkgs.nerd-icons-completion
      epkgs.nerd-icons-corfu
      epkgs.nerd-icons-dired
    ];
  };

  nix-ts-mode = {
    enable = true;
    init = readInit "nix-ts-mode.el";
    packages = epkgs: _: [ epkgs.nix-ts-mode ];
  };

  plantuml-mode = {
    enable = true;
    init = readInit "plantuml-mode.el";
    packages = epkgs: _: [ epkgs.plantuml-mode ];
  };

  pr-review = {
    enable = true;
    init = readInit "pr-review.el";
    packages = epkgs: _: [ epkgs.pr-review ];
  };

  project = {
    enable = true;
    init = readInit "project.el";
    packages = _epkgs: _: [ ];
  };

  scroll-bar = {
    enable = true;
    init = readInit "scroll-bar.el";
    packages = _epkgs: _: [ ];
  };

  help = {
    enable = true;
    init = readInit "help.el";
    packages = _epkgs: _: [ ];
  };

  man = {
    enable = true;
    init = readInit "man.el";
    packages = _epkgs: _: [ ];
  };

  tool-bar = {
    enable = true;
    init = readInit "tool-bar.el";
    packages = _epkgs: _: [ ];
  };

  mouse = {
    enable = true;
    init = readInit "mouse.el";
    packages = _epkgs: _: [ ];
  };

  magit = {
    enable = true;
    init = readInit "magit.el";
    packages = epkgs: _: [ epkgs.magit ];
  };

  markdown-ts-mode = {
    enable = true;
    init = readInit "markdown-ts-mode.el";
    # Emacs 31 ships `markdown-ts-mode` built in (same feature name and
    # `markdown-ts-mode-map`), and the ELPA package refuses to load
    # beside it, so it is only installed for older Emacsen.
    packages =
      epkgs: local:
      (if builtins.compareVersions epkgs.emacs.version "31" < 0 then [ epkgs.markdown-ts-mode ] else [ ])
      ++ [ local.markdown-table-fix ];
  };

  mermaid-ts-mode = {
    enable = true;
    init = readInit "mermaid-ts-mode.el";
    packages = epkgs: local: [
      epkgs.mermaid-ts-mode
      local.mermaid-preview
    ];
  };

  render-dwim = {
    enable = true;
    init = readInit "render-dwim.el";
    packages = _epkgs: local: [ local.render-dwim ];
  };

  ghostel = {
    enable = true;
    init = readInit "ghostel.el";
    # evil-ghostel is listed alongside the core even though
    # ch-evil-ghostel already pulls it in, so the package manifest
    # records the version it was built at: it comes from ghostel's own
    # source tree via an overlay, not from emacs-overlay's package set.
    packages = epkgs: local: [
      epkgs.ghostel
      epkgs.evil-ghostel
      local.ch-evil-ghostel
      local.ghostel-funcs
    ];
  };

  speedbar = {
    enable = true;
    init = readInit "speedbar.el";
    # nerd-icons supplies the PR tree's file/directory glyphs; listed
    # here so the bundle stands alone if the nerd-icons bundle is off.
    packages = epkgs: _: [ epkgs.nerd-icons ];
  };

  treesit-fold = {
    enable = true;
    init = readInit "treesit-fold.el";
    packages = epkgs: _: [ epkgs.treesit-fold ];
  };

  typescript-ts-mode = {
    enable = true;
    init = readInit "typescript-ts-mode.el";
    packages = _epkgs: _: [ ];
  };

  vundo = {
    enable = true;
    init = readInit "vundo.el";
    packages = epkgs: _: [ epkgs.vundo ];
  };

  which-key = {
    enable = true;
    init = readInit "which-key.el";
    packages = _epkgs: _: [ ];
  };

  window-funcs = {
    enable = true;
    init = readInit "window-funcs.el";
    packages = _epkgs: local: [ local.window-funcs ];
  };
}
