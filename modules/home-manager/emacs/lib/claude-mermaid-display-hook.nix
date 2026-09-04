# SPDX-License-Identifier: MIT
# The mermaid-rendering MessageDisplay hook as a package (script and
# rationale in claude-mermaid-display-hook.sh); built here rather
# than inline in the module so the flake check can drive it with
# synthetic payloads.  merman supplies the mmdc-compatible renderer
# on the hook's own PATH.
{ pkgs, merman }:
pkgs.writeShellApplication {
  name = "claude-mermaid-display-hook";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.findutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.jq
    merman
  ];
  text = builtins.readFile ./claude-mermaid-display-hook.sh;
}
