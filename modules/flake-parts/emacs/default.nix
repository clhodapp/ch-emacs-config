# SPDX-License-Identifier: MIT
# The Emacs flake module: for a flake-parts consumer that composes its
# package sets with caisson's nixpkgs module, registers this flake's
# Emacs overlays so they can be selected by name. It imports only
# caisson's nixpkgs-interface module (the registry declaration), not the
# package-set machinery.
#
# The overlays and the home-manager module are also plain flake outputs
# (`overlays.emacs`, `overlays.emacs-packages`, `modules.homeManager.emacs`);
# a consumer without flake-parts uses those directly. See the README.
{ closure-inputs, mkModule, ... }:
{ ... }:
{
  imports = [
    (mkModule ./nixpkgs)
    closure-inputs.caisson.flakeModules.nixpkgs-interface
  ];
}
