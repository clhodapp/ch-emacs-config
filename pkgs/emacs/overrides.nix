# SPDX-License-Identifier: MIT
# Small emacsPackages overrides layered on top of emacs-overlay.
{
  lib,
  pkgs,
  # Sources of the packages consumed as plain (non-flake) inputs, keyed by
  # package name; each has a package.nix under this directory.
  sources,
  ...
}:
self: super: {
  pr-review = self.callPackage ./pr-review/package.nix { src = sources.pr-review; };

  # Carry a one-line upstream bug fix until upstream takes it.
  #
  # `adjustGlyph' scales a fallback-font glyph to fit the terminal cell, but
  # the scale has a floor and no ceiling.  When the fallback glyph is SMALLER
  # than the cell on every axis, all three ratios exceed 1, their minimum is
  # still above 1, and the glyph is scaled UP until the row outgrows the cell.
  # `ghostel--anchor-window' re-derives `window-start' from a pixel measurement
  # on every redraw, so a row that grows by a pixel shifts the whole viewport;
  # an animating TUI spinner then makes the buffer jitter several times a
  # second.
  #
  # Reached by weight, not by the glyph: Claude Code draws some spinner states
  # bold, Hack Nerd Font has none of the spinner asterisks, and while the
  # regular fallback is Unifont (which has no bold face), the bold fallback is
  # DejaVu Sans Mono Bold, smaller than the Hack cell on every side.  Measured:
  # bold frames realize 21px rows against a 19px cell, non-bold frames 19px.
  #
  # Upstream fixed the oversized-glyph direction in dakra/ghostel#407; this is
  # the undersized direction, still unfixed as of 0.52.0.  Drop this attribute
  # once upstream clamps the scale at 1.0.  `--replace-fail' means a source
  # change breaks the build rather than silently skipping the patch.
  #
  # Only the native module is rebuilt, so `evil-ghostel' below still reads the
  # unchanged `src' and `version'.
  ghostel =
    let
      patchedModule = super.ghostel.module.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/Renderer.zig \
            --replace-fail \
              'const computed_scale = @min(scale_width, @min(scale_ascent, scale_descent));' \
              'const computed_scale = @min(1.0, @min(scale_width, @min(scale_ascent, scale_descent)));'
        '';
      });
    in
    super.ghostel.overrideAttrs (old: {
      preBuild = ''
        install ${patchedModule}/ghostel-module.so ghostel-module.so
      '';
      passthru = (old.passthru or { }) // {
        module = patchedModule;
      };
    });

  # ghostel ships its evil integration under extensions/, which its own
  # recipe does not install (melpa's :defaults takes top-level .el only).
  # Build it from the same source as the core, so the two cannot drift:
  # this file advises ghostel internals, and a version skew between them
  # is what the vendored copy this replaces existed to paper over.
  evil-ghostel = self.callPackage ./evil-ghostel/package.nix {
    src = self.ghostel.src;
    inherit (self.ghostel) version;
  };

  shell-maker = super.shell-maker.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      sed -i "/(require 'org-faces)/a (declare-function org-format-latex \"org\" t)" markdown-overlays.el
    '';
  });
}
