# SPDX-License-Identifier: MIT
{
  lib,
  pkgs,
  emacsPackage,
  bundles,
  sources,
  emacsOverlayRev ? null,
}:
let
  version = emacsPackage.version or "0";
  emacsOverrides = import ../../../../pkgs/emacs/overrides.nix {
    inherit lib pkgs sources;
  };
  epkgs = (pkgs.emacsPackagesFor emacsPackage).overrideScope emacsOverrides;
  bundleLib = import ./bundles.nix { inherit lib; };
  local = import ../packages/scope.nix { inherit epkgs version; };

  localPnames = [
    "ch-emacs-config-default"
    "ch-evil-ghostel"
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
    map (bundleName: expandBundlePackages bundleName (bundles.${bundleName}.packages epkgs local)) (
      bundleLib.orderedNames bundles
    )
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
  emacsVersion = emacsPackage.version or null;
  inherit emacsOverlayRev;
  packages = lib.sort (a: b: a.pname < b.pname) allEntries;
}
