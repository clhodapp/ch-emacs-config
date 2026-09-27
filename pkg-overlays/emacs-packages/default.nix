# SPDX-License-Identifier: MIT
#
# emacs-overlay's ELPA/MELPA package pins, the Emacs package set the
# configuration is built and checked against. It is a registry entry of
# its own, so a project that imports it and another that imports it too
# apply it once, and a consumer can replace it under its key.
{ closure-inputs, ... }:
{
  overlay = closure-inputs.emacs-overlay.overlays.package;
}
