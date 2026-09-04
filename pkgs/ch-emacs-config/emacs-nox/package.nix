# SPDX-License-Identifier: MIT
{ lib, pkgs }:
import ../emacs-base.nix { inherit lib pkgs; } "-nox"
