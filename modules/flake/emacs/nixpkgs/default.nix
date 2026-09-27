# SPDX-License-Identifier: MIT
{ closure-inputs, closure-lib, ... }:
{ ... }:
{
  # Registration only: the consumer selects these from
  # `caisson.nixpkgs.pkgSets.<set>.overlayImports` (and from
  # `caisson.nixpkgs.overlays.exported`, if it re-exports). Both default to
  # every registered overlay, so a consumer on the defaults applies and
  # re-exports these without naming them.
  #
  # The registry applies the CONSUMER's namespace to each entry, so each
  # value ignores the name it is given: the package overlay comes from
  # this flake's library already bound to the `ch-emacs-config` scope
  # name, and registering the raw package function would put the packages
  # under `pkgs.<consumer>` instead.
  caisson.nixpkgs.overlays.all = {
    # `pkgs.ch-emacs-config.emacs`, `.emacs-pgtk`, `.emacs-nox`: the Emacs
    # base packages the configuration is validated against.
    ch-emacs-config-emacs = _: closure-lib.ch-emacs-config.packagesOverlay;
    # emacs-overlay's ELPA/MELPA package pins, the package set the checks
    # build the configuration against. Replaces `emacsPackagesFor`.
    ch-emacs-config-emacs-packages = _: closure-inputs.emacs-overlay.overlays.package;
  };
}
