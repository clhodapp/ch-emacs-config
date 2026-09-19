# SPDX-License-Identifier: MIT
#
# The fonts the init names, and the init lines that set the faces and
# fontsets using them. The executables table (./executables.nix) pins
# programs by store path; a font cannot be pinned that way, because Emacs
# resolves a font by FAMILY through fontconfig rather than by path, so
# the package has to be installed for the name to resolve. This table
# therefore carries both halves: the package the Home Manager module
# installs, and the family name the init asks for.
#
# Each entry is a package or null. A package is installed into the
# profile and its family named in the init. Null leaves the font to the
# host, and the init line that names it is omitted rather than left
# pointing at a family that may not resolve, so a missing font degrades
# to Emacs's own default instead of a face that silently does not apply.
{ lib, pkgs }:
let
  elispString = s: ''"${s}"'';

  # One entry per font: the package providing it, the family name the
  # init asks fontconfig for, and what uses it.
  fontTable = {
    default = {
      default = pkgs.monaspace;
      defaultText = "pkgs.monaspace";
      family = "Monaspace Neon";
      description = ''
        The default face. Monaspace draws seven weights at one advance
        width, which is what lets faces separate levels by weight; a
        two-weight font collapses any such ramp, because fontconfig
        rounds an intermediate weight to the nearest one present.
      '';
    };
    symbols = {
      default = pkgs.nerd-fonts.symbols-only;
      defaultText = "pkgs.nerd-fonts.symbols-only";
      family = "Symbols Nerd Font Mono";
      description = ''
        The icons nerd-icons draws, as an icons-only font rather than
        patched into the default face's font. It carries no text glyphs,
        so it cannot shadow the default face, and its Mono variant draws
        each icon one cell wide, which dired's column alignment assumes.
        This is nerd-icons' own default family, so nothing in the init
        has to name it while it is installed.
      '';
    };
    emoji = {
      default = pkgs.noto-fonts-color-emoji;
      defaultText = "pkgs.noto-fonts-color-emoji";
      family = "Noto Color Emoji";
      description = "Colour emoji, preferred over the monochrome fallback.";
    };
    emojiFallback = {
      # Symbola is unfree, and everything else here is free, so it is not
      # a default: taking it would force allowUnfree on every consumer
      # for a fallback font. Set this to pkgs.symbola to get it.
      default = null;
      defaultText = "null";
      family = "Symbola";
      description = ''
        Monochrome coverage for emoji and symbols the colour font lacks,
        registered under it in the emoji fontset. No default, because the
        font this names (`pkgs.symbola`) is unfree and the rest of this
        package set is not; set it explicitly to install it.
      '';
    };
  };
in
{
  table = fontTable;

  # The face and fontset lines for FONTS (an attrset shaped like `table`,
  # values packages or null). An entry set to null contributes nothing,
  # so the init never names a family the profile does not provide.
  initContent =
    { fonts, defaultHeight }:
    let
      present = name: fonts.${name} or null != null;
      family = name: elispString fontTable.${name}.family;

      sections = lib.concatStrings [
        (lib.optionalString (present "default") ''
          (custom-set-faces
           '(default ((t (:font ${family "default"} :height ${toString defaultHeight})))))
        '')
        # Order matters: the monochrome fallback is registered first and
        # the colour font prepended over it, so colour wins where both
        # cover a character.
        (lib.optionalString (present "emojiFallback") ''
          (set-fontset-font t 'emoji ${family "emojiFallback"})
        '')
        (lib.optionalString (present "emoji") ''
          (set-fontset-font t 'emoji (font-spec :family ${family "emoji"}) nil 'prepend)
        '')
      ];
    in
    lib.optionalString (sections != "") ''
      ;; Fonts the init names (modules/home-manager/emacs/lib/fonts.nix).
      ;; The Home Manager module installs each one it names here, so a
      ;; family named below resolves through fontconfig.
      ${sections}
    '';
}
