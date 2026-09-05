# SPDX-License-Identifier: MIT
#
# The local (in-tree) Emacs packages. `mkLocalBuild` is exported
# alongside them so a layer built on this configuration can build its
# own packages the same way, without reimplementing the builder.
{
  epkgs,
  version,
}:
let
  mkLocalBuild = epkgs.callPackage ./builders/local { };
in
{
  inherit mkLocalBuild;
  evil-ghostel = epkgs.callPackage ./evil-ghostel {
    inherit mkLocalBuild version;
    ghostel = epkgs.ghostel;
    evil = epkgs.evil;
  };
  ghostel-funcs = epkgs.callPackage ./ghostel-funcs {
    inherit mkLocalBuild version;
    ghostel = epkgs.ghostel;
  };
  markdown-table-fix = epkgs.callPackage ./markdown-table-fix {
    inherit mkLocalBuild version;
  };
  mermaid-preview = epkgs.callPackage ./mermaid-preview {
    inherit mkLocalBuild version;
  };
  render-dwim = epkgs.callPackage ./render-dwim {
    inherit mkLocalBuild version;
  };
  window-funcs = epkgs.callPackage ./window-funcs {
    inherit mkLocalBuild version;
  };
}
