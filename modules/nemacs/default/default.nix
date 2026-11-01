# SPDX-License-Identifier: MIT
#
# The ch-emacs-config configuration, as a nemacs module: its bundles,
# its packages, its init and early init, and the programs and fonts the
# init names. Evaluating it with nemacs builds the editor; the Home
# Manager module `emacs` puts it in `programs.nemacs.settings`.
{ mkModule, ... }:
{ ... }:
{
  imports = [
    (mkModule ./ch-emacs-config)
  ];
}
