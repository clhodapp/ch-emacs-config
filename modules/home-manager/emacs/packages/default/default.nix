# SPDX-License-Identifier: MIT
{
  mkLocalBuild,
  pkgs,
  use-package,
  extraInitContent ? "",
  bundleInitContent ? "",
  bundlePackages ? [ ],
  version,
}:
let
  lib = pkgs.lib;
  preambleEl = builtins.readFile ./preamble.el;
  footerEl = builtins.readFile ./footer.el;
  defaultEl = lib.concatStrings [
    preambleEl
    "\n\n"
    bundleInitContent
    "\n\n"
    footerEl
    (lib.optionalString (extraInitContent != "") ''

      ;; ch-emacs-config downstream init
      ${extraInitContent}
    '')
  ];
  src = pkgs.runCommand "ch-emacs-config-default-package-src" { } ''
    mkdir $out
    cp ${pkgs.writeText "ch-emacs-config-default.el" defaultEl} $out/ch-emacs-config-default.el
  '';
in
mkLocalBuild {
  pname = "ch-emacs-config-default";
  inherit version src;
  packageRequires = [ use-package ] ++ bundlePackages;

  postInstall = ''
    cat >> "$out/share/emacs/site-lisp/elpa/ch-emacs-config-default-${version}/ch-emacs-config-default-autoloads.el" <<'EOF'
    (eval-after-load 'package
      (lambda ()
        (require 'ch-emacs-config-default)))
    EOF
  '';
}
