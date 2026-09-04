# SPDX-License-Identifier: MIT
{
  epkgs,
  version,
}:
let
  mkLocalBuild = epkgs.callPackage ./builders/local { };
  semantic-finder = epkgs.callPackage ./semantic-finder {
    inherit mkLocalBuild version;
  };
in
{
  inherit mkLocalBuild semantic-finder;
  ai-commit = epkgs.callPackage ./ai-commit {
    inherit mkLocalBuild version;
  };
  claude-queue = epkgs.callPackage ./claude-queue {
    inherit mkLocalBuild version semantic-finder;
  };
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
