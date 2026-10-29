# SPDX-License-Identifier: MIT
# Canonical language-server table for LSP clients configured from Nix
# (emacs/eglot, an agent's LSP plugin). One entry per server process:
# the exact argv that spawns it (store-pinned, PATH plays no part), the
# file extensions it owns mapped to LSP languageId values, and any
# workspace-configuration settings. Client-specific facts (emacs
# major-mode wiring, plugin manifest shape) stay with the consuming
# module; a server belongs here once two clients spawn it.
#
# Keys name the server as the client sees it; a muxed stack is named for
# what it composes (ty-ruff), never for the mux that glues it, since the
# same mux could back other combinations.
#
# `merman-lsp` needs merman, which is not in nixpkgs, so it has no
# default: pass the package (github:clhodapp/merman-nix exports it as
# merman-preview), or null to leave the entry out. The obvious default,
# `pkgs.merman-nix.merman-preview` from that flake's overlay, holds only
# where the caller applied the
# overlay, and the callers that matter are Home Manager modules
# evaluated against a consumer's package set that carries no overlay of
# ours.
pkgs:
{
  merman,
}:
let
  inherit (pkgs) lib;
in
lib.optionalAttrs (merman != null) {
  merman-lsp = {
    cmd = [ "${merman}/bin/merman-lsp" ];
    extensionToLanguage = {
      ".mmd" = "mermaid";
      ".mermaid" = "mermaid";
    };
  };
}
// {
  nil = {
    cmd = [ (lib.getExe pkgs.nil) ];
    extensionToLanguage = {
      ".nix" = "nix";
    };
    settings.nil.formatting.command = [ (lib.getExe pkgs.nixfmt) ];
  };

  # ty (types/navigation) + ruff (lint/fixes/formatting) behind the
  # rassumfrassum mux, presented as one server per buffer/file.
  ty-ruff = {
    cmd = [
      "${pkgs.rassumfrassum}/bin/rass"
      "--"
      "${lib.getExe pkgs.ty}"
      "server"
      "--"
      "${lib.getExe pkgs.ruff}"
      "server"
    ];
    extensionToLanguage = {
      ".py" = "python";
      ".pyi" = "python";
    };
  };

  marksman = {
    cmd = [
      "${lib.getExe pkgs.marksman}"
      "server"
    ];
    extensionToLanguage = {
      ".md" = "markdown";
    };
  };

  typescript-language-server = {
    cmd = [
      "${lib.getExe pkgs.typescript-language-server}"
      "--stdio"
    ];
    extensionToLanguage = {
      ".ts" = "typescript";
      ".tsx" = "typescriptreact";
      ".js" = "javascript";
      ".jsx" = "javascriptreact";
      ".mjs" = "javascript";
      ".cjs" = "javascript";
    };
  };

  # The server runs the project's own cargo and rustc, found on PATH
  # (envrc puts a dev shell's toolchain there), so the toolchain is not
  # pinned. nixpkgs' wrapper defaults RUST_SRC_PATH to nixpkgs' own
  # standard-library source, which rust-analyzer then reads in place of
  # the source that ships with the toolchain. A dev shell that sets
  # RUST_SRC_PATH overrides the default.
  rust-analyzer = {
    cmd = [ (lib.getExe pkgs.rust-analyzer) ];
    extensionToLanguage = {
      ".rs" = "rust";
    };
  };

  vscode-json-language-server = {
    cmd = [
      "${pkgs.vscode-langservers-extracted}/bin/vscode-json-language-server"
      "--stdio"
    ];
    extensionToLanguage = {
      ".json" = "json";
    };
  };

  # The server shells out for two of its features: shellcheck for
  # diagnostics and shfmt for formatting. Both are looked up by the
  # path in its own settings (default: bare names on PATH), so pin them
  # there; nixpkgs' wrapper only suffixes PATH with shellcheck, which a
  # different shellcheck earlier on PATH would shadow.
  bash-language-server = {
    cmd = [
      (lib.getExe pkgs.bash-language-server)
      "start"
    ];
    extensionToLanguage = {
      ".sh" = "shellscript";
      ".bash" = "shellscript";
    };
    settings.bashIde = {
      shellcheckPath = lib.getExe pkgs.shellcheck;
      shfmt.path = lib.getExe pkgs.shfmt;
    };
  };
}
