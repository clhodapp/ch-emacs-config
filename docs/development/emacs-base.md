# Emacs base package selection

How the flake decides which Emacs the configuration is built against, and how that decision reaches consumers.

## The selection

`pkgs/ch-emacs-config/emacs-base.nix` holds a list of supported majors, newest first. For a toolkit variant (`""`, `-pgtk`, `-nox`) it returns the first `emacs<major><variant>` attribute the nixpkgs instance carries as a final release. "Final release" means the version string is `<major>.<minor>` with a non-zero minor: pretests are `<major>.0.<nn>` and release candidates carry an `-rcN` suffix, and Nix's `compareVersions` orders both above the release they precede, so a plain `versionAtLeast` would accept them. If no listed major is present, evaluation fails with a message naming the list.

nixpkgs ships a new major as `emacs<NN>-*` before it moves the unversioned `emacs-*` attributes, which is why the selection names majors rather than reading `pkgs.emacs`. A major joins the list once the configuration byte-compiles under it (the config package is compiled with `byte-compile-error-on-warn`, so obsolescence warnings are fatal) and the checks pass.

## Where it is exposed

- `overlays.emacs` (registered as `caisson.nixpkgs.overlays.all.emacs` in `configs/flake-parts/default/default.nix` and exported) adds `pkgs.ch-emacs-config.emacs`, `.emacs-pgtk`, `.emacs-nox`.
- `modules.homeManager.emacs` defaults `ch-emacs-config.emacs.package` to `pkgs.ch-emacs-config.emacs`, with a `throw` that names the overlay when it is absent. The module itself uses only standard module arguments; it does not depend on the framework.
- `flakeModules.emacs` registers `overlays.emacs` and `overlays.emacs-packages` into a flake-parts consumer's `caisson.nixpkgs.overlays.all` registry (names `ch-emacs-config-emacs`, `ch-emacs-config-emacs-packages`). It imports only caisson's `flakeModules.nixpkgs-interface`. The registered values are the already-exported overlays, bound to this flake's name: the registry applies the consumer's `configName` to each entry, so registering the raw `mkPackagesOverlay` function would put the packages under `pkgs.<consumer>`.

## Why the checks build against the overlay

The checks partition composes its package set as `caisson.nixpkgs.pkgSets.pkgs` with `overlays.emacs-packages` then `overlays.emacs`, and every Emacs-building check uses `pkgs.ch-emacs-config.emacs` or `.emacs-pgtk`. The proposed base and the validated base are therefore one expression; a nixpkgs bump that brings a new listed major as a final release is validated by this repo's CI, not discovered by a consumer's build. The `emacs-home-manager-module` check leaves `package` at its default for the same reason.

`tests/integration/plain-consumer` is a flake with no flake-parts and no `ch-*` inputs that applies the overlays with `import nixpkgs` and builds a home configuration with `homeManagerConfiguration`. It holds the README's first recipe and the rule that exports must work for a plain flake.
