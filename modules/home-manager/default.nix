# SPDX-License-Identifier: MIT
{ lib }:
{
  emacs = lib.caisson-core.mkModule "homeManager" ./emacs;
}
