# SPDX-License-Identifier: MIT
# Small emacsPackages overrides layered on top of emacs-overlay.
{
  pkgs,
  # Sources of the packages consumed as plain (non-flake) inputs, keyed by
  # package name; each has a package.nix under this directory.
  sources,
  ...
}:
self: super: {
  pr-review = self.callPackage ./pr-review/package.nix { src = sources.pr-review; };

  # Two upstream bug fixes, carried until upstream takes them.  Neither is
  # filed as of 0.56.0.  `--replace-fail' means a source change that moves
  # either line breaks the build rather than silently skipping the patch.
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
  # Drop the first patch once upstream clamps the scale at 1.0.  Upstream
  # handles the oversized direction already (dakra/ghostel#407); this is the
  # undersized one.
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
  # Measured: following text lands at exactly 2.00 columns at scales 0, +2
  # and +4.  Drop this patch once upstream reserves the scaled width.
  #
  # The `ghostel' flake input supplies the source, because 0.54.0 fixed mouse
  # cells under `text-scale-mode' (dakra/ghostel#676) and nixpkgs still ships
  # 0.53.0.  nixpkgs remains the build recipe; `version', `src' and `zigDeps'
  # are the whole of the override, and all three go once the pinned nixpkgs
  # reaches 0.54.0 or later.
  #
  # `zigDeps' is a fixed-output derivation over the source, so it is refetched
  # here and its hash tracks the pin.  `passthru.module' reads `src', `version'
  # and `zigDeps' back through `finalAttrs', hence the two-argument form.
  #
  # `evil-ghostel' below builds from `self.ghostel.src', so it follows this
  # pin too.
  ghostel = super.ghostel.overrideAttrs (
    finalAttrs: old: {
      version = "0.56.0";
      src = sources.ghostel;
      zigDeps = finalAttrs.zig.fetchDeps {
        inherit (finalAttrs) src pname version;
        fetchAll = true;
        hash = "sha256-87q0nSOkZaIHW8Ztgf5pR13sHNw7eQKJhu12QjRMTvA=";
      };
      passthru = old.passthru // {
        # nixpkgs' `preBuild' installs `finalPackage.module', so patching
        # the module here is enough for the elisp package to ship it.
        module = old.passthru.module.overrideAttrs (m: {
          inherit (finalAttrs) src version zigDeps;
          postPatch = (m.postPatch or "") + ''
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
      };
    }
  );

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
