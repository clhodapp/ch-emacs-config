# SPDX-License-Identifier: MIT
{ closure-inputs, ... }:
{ ... }:
{
  # Registration only: the consumer selects these from
  # `caisson.nixpkgs.pkgSets.<set>.overlayImports` (and from
  # `caisson.nixpkgs.overlays.exported`, if it re-exports). Both default to
  # every registered overlay, so a consumer on the defaults applies and
  # re-exports these without naming them.
  #
  # The registry applies the CONSUMER's configName to each entry, so the
  # values are this flake's exported overlays, already bound to the
  # `ch-emacs-config` name; registering the raw package function would
  # put the packages under `pkgs.<consumer>` instead.
  caisson.nixpkgs.overlays.all = {
    # `pkgs.ch-emacs-config.emacs`, `.emacs-pgtk`, `.emacs-nox`: the Emacs
    # base packages the configuration is validated against.
    ch-emacs-config-emacs = _: closure-inputs.self.overlays.emacs;
    # emacs-overlay's ELPA/MELPA package pins, the package set the checks
    # build the configuration against. Replaces `emacsPackagesFor`.
    ch-emacs-config-emacs-packages = _: closure-inputs.self.overlays.emacs-packages;
  };
}
