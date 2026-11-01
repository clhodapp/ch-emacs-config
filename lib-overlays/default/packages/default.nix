# SPDX-License-Identifier: MIT
#
# The in-tree Emacs packages, as an overlay on a nemacs package set:
# each is built with the set's `nemacsBuild`, at the version of its
# Emacs, and lands in the set under its own name, so a bundle names it
# as `epkgs.<name>` and a layer above can depend on it the same way.
final: _prev:
let
  version = final.emacs.version or "0";
in
{
  ghostel-funcs = final.callPackage ./ghostel-funcs { inherit version; };
  ch-evil-ghostel = final.callPackage ./ch-evil-ghostel { inherit version; };
  gh-review = final.callPackage ./gh-review { inherit version; };
  markdown-table-fix = final.callPackage ./markdown-table-fix { inherit version; };
  mermaid-preview = final.callPackage ./mermaid-preview { inherit version; };
  render-dwim = final.callPackage ./render-dwim { inherit version; };
  window-funcs = final.callPackage ./window-funcs { inherit version; };
}
