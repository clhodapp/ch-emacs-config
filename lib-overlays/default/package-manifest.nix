# SPDX-License-Identifier: MIT
#
# CONFIG is the `config` of a nemacs evaluation: the manifest lists the
# packages of its enabled bundles, from its package set, in the order
# its init runs them.
{
  lib,
  pkgs,
  config,
  emacsOverlayRev ? null,
}:
let
  inherit (config) bundles;
  epkgs = config.build.epkgs;

  orderedNames = lib.sort (
    a: b:
    if bundles.${a}.order != bundles.${b}.order then bundles.${a}.order < bundles.${b}.order else a < b
  ) (builtins.attrNames (lib.filterAttrs (_name: bundle: bundle.enable) bundles));

  localPnames = [
    "nemacs-init"
    "ch-evil-ghostel"
    "gh-review"
    "ghostel-funcs"
    "markdown-table-fix"
    "window-funcs"
  ];

  overriddenPnames = [ "shell-maker" ];

  treesitGrammarAttrs = [
    "tree-sitter-bash"
    "tree-sitter-java"
    "tree-sitter-javascript"
    "tree-sitter-json"
    "tree-sitter-markdown"
    "tree-sitter-markdown-inline"
    "tree-sitter-nix"
    "tree-sitter-python"
    "tree-sitter-ruby"
    "tree-sitter-rust"
    "tree-sitter-toml"
    "tree-sitter-tsx"
    "tree-sitter-typescript"
    "tree-sitter-yaml"
  ];

  packageMeta =
    pkg:
    let
      drvName = builtins.parseDrvName (pkg.name or "unknown");
    in
    {
      pname = pkg.pname or drvName.name;
      version = pkg.version or drvName.version;
      rev = pkg.src.rev or pkg.src.tag or null;
    };

  classifySource =
    pname:
    if lib.elem pname localPnames then
      "local"
    else if lib.elem pname overriddenPnames then
      "override"
    else if lib.hasPrefix "tree-sitter-" pname then
      "treesit-grammar"
    else
      "epkgs";

  entryFor =
    {
      bundle,
      pkg,
      attr ? null,
    }:
    let
      meta = packageMeta pkg;
      source = classifySource meta.pname;
    in
    {
      inherit (meta) pname version rev;
      inherit bundle attr source;
      patched = source == "override";
    };

  isTreesitWrapper = pkg: (builtins.parseDrvName (pkg.name or "")).name == "emacs-treesit-grammars";

  treesitGrammarEntries =
    bundle:
    map (
      attr:
      entryFor {
        inherit bundle;
        pkg = pkgs.tree-sitter.builtGrammars.${attr};
        inherit attr;
      }
    ) treesitGrammarAttrs;

  expandBundlePackages =
    bundleName: pkgsList:
    lib.concatLists (
      map (
        pkg:
        if isTreesitWrapper pkg then
          treesitGrammarEntries bundleName
        else
          [
            (entryFor {
              bundle = bundleName;
              pkg = pkg;
            })
          ]
      ) pkgsList
    );

  bundleEntries = lib.concatLists (
    map (
      bundleName: expandBundlePackages bundleName (bundles.${bundleName}.packages epkgs)
    ) orderedNames
  );

  implicitEntries = [
    (entryFor {
      bundle = "default";
      pkg = epkgs.use-package;
      attr = "use-package";
    })
  ];

  # Dependencies of local packages that are not already pulled in by bundles.
  dependencyEntries = [
    (entryFor {
      bundle = "dependency";
      pkg = epkgs.shell-maker;
      attr = "shell-maker";
    })
  ];

  dedupeKey = entry: "${entry.pname}@${entry.version}";

  dedupeEntries =
    entries:
    lib.attrValues (
      lib.foldl' (
        acc: entry:
        acc
        // {
          ${dedupeKey entry} = entry;
        }
      ) { } entries
    );

  allEntries = dedupeEntries (bundleEntries ++ implicitEntries ++ dependencyEntries);
in
{
  emacsVersion = config.package.version or null;
  inherit emacsOverlayRev;
  packages = lib.sort (a: b: a.pname < b.pname) allEntries;
}
