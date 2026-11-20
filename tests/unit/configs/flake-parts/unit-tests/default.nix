# SPDX-License-Identifier: MIT
{ ... }:
{
  systems = [ "x86_64-linux" ];

  perSystem =
    { pkgs, ... }:
    {
      checks.smoke-success = pkgs.runCommand "unit-smoke-success" { } "touch $out";
    };
}
