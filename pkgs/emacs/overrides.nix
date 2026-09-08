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
  # The second patch is the horizontal counterpart, visible only under
  # `text-scale-mode'.  When a fallback glyph claims a second column, the
  # renderer reserves it with `(min-width (2))': two columns of the FRAME's
  # default face, which a buffer-local text scale does not change.  At scale +2
  # the cell is 14px, so two cells are 28px, but the reservation is 20px; the
  # glyph's 23px of ink overruns it and Emacs advances by the ink, so the rest
  # of that line lands 5px short of the column grid.  Frames whose glyph makes
  # no claim land on the grid, and the line shifts as the spinner animates.
  # The renderer already has the scaled width as `slot_width'; emit that in
  # pixels, `(min-width ((PIXELS)))', so the reservation follows the scale.
  # Measured: following text lands at exactly 2.00 columns at scales 0, +2 and
  # +4 (was 1.64 and 1.65 columns).  Unfixed upstream as of 0.53.0.
  #
  # The third patch is in the elisp: dakra/ghostel#676.
  #
  # Every mouse handler turns the event's pixel position into a terminal
  # cell with `posn-col-row' and no USE-WINDOW argument, which divides by
  # the frame's default character size.  A buffer-local font change
  # (`text-scale-mode') leaves the reported grid correct but scales the sent
  # column and row up by the same factor, so a program with mouse tracking
  # (Claude Code, htop) acts on a cell to the right of and below the pointer.
  # With USE-WINDOW the division uses the window's font.  That form drops
  # the `line-spacing' term from the row division; nothing here sets
  # `line-spacing', so for this configuration it is the whole fix (the fix
  # proposed upstream keeps the spacing).  Drop the `postPatch' once the
  # pinned overlay carries the upstream fix.
  #
  # None of the three patches touches `src' or `version', so `evil-ghostel'
  # below still builds from the unpatched source; it has no `posn-col-row'
  # call.
  ghostel =
    let
      patchedModule = super.ghostel.module.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/Renderer.zig \
            --replace-fail \
              'const computed_scale = @min(scale_width, @min(scale_ascent, scale_descent));' \
              'const computed_scale = @min(1.0, @min(scale_width, @min(scale_ascent, scale_descent)));'
          substituteInPlace src/Renderer.zig \
            --replace-fail \
              'const min_width_spec = env.list(.{ s.@"min-width", env.list(.{char_width}) });' \
              'const min_width_spec = env.list(.{ s.@"min-width", env.list(.{env.list(.{slot_width})}) });'
        '';
      });
    in
    super.ghostel.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace lisp/ghostel.el \
          --replace-fail '(posn-col-row posn))' '(posn-col-row posn t))'
      '';
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
