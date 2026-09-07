# ch-emacs-config

A declarative Emacs configuration as a Home Manager module: the editor,
its packages, its init, and a daemon that survives generation switches,
all built from Nix.

## What it provides

**Bundles.** Features are grouped rather than listed one package at a
time. Enabling the `eglot` bundle brings the language-server wiring, its
init, and the packages behind it; the same for `jinx` spell checking,
`consult-gh`, `render-dwim`, and the rest. A bundle is the unit you turn
on.

**A daemon with custody rules.** The systemd unit is keyed by a hash of
the Emacs generation, so a rebuild starts the new daemon rather than
leaving the old one serving stale code. A rotating daemon's exit must
not delete the socket the new generation owns, which is asserted by a
check rather than hoped for: the exit unlink happens through two paths,
and an Emacs bump that renames either one fails the build.

**Launchers that resolve at run time.** The desktop entry and `$EDITOR`
point at scripts in the profile, and those scripts find the daemon and
`emacsclient` when they run rather than when they were built. Desktop
caches, taskbar pins, and long-lived shells all capture what they saw at
index time and never notice a profile switch, so a launcher with baked
paths eventually drives a daemon that no longer exists.

**Language servers from a shared table.** The eglot configuration
renders one table of servers (`modules/home-manager/lib/language-servers.nix`,
exported as `languageServerTable`), which any other LSP client
configured alongside this editor can read, so two clients on one
project cannot disagree about how to spawn a server.

## Use it

```nix
{
  inputs.ch-emacs-config.url = "github:clhodapp/ch-emacs-config";

  # in a Home Manager configuration:
  #   ch-emacs-config.emacs.enable = true;
}
```

The flake also exports the Emacs packages it validates against
(`emacs`, `emacs-pgtk`, `emacs-nox`) and an overlay carrying them.

## Development

`nix flake check` builds both Emacs variants, boots each as a daemon and
probes init health over `emacsclient`, batch-loads the full init the way
real startup does, runs the ERT suites for the packages defined here,
and evaluates the Home Manager module end to end. A plain-flake consumer
without flake-parts is held as a check too, so the README's simplest
recipe cannot rot.

`nix fmt` formats.

In CI the same `nix flake check` runs with the Nix store cached between
runs, since a cold runner native-compiles the whole Emacs package set
and takes most of an hour. A pull request that leaves `.github/` alone
is checked by `main`'s copy of the workflow, in `main`'s context once
its own check completes, and adds its build to the shared cache; one
that changes the pipeline is checked by its own copy, under a cache
only it can see. The comments at the top of the two
workflow files say why that split is what makes the cache safe to write
from a pull request.

## Binary cache

What `main` builds is pushed to the `clhodapp` cachix cache, signed with
its key, so a consumer at the same pins substitutes the compiled package
set instead of native-compiling it. That cache skips paths its upstreams
already hold, so using it means using them too:

| Substituter | Public key |
|---|---|
| `https://clhodapp.cachix.org` | `clhodapp.cachix.org-1:EW/0conxH0OQyo0o4ub/grdkFspholmQMSnQyj0vrZI=` |
| `https://nix-community.cachix.org` | `nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=` |
| `https://numtide.cachix.org` | `numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE=` |

The flake's `nixConfig` declares all three, so a direct `nix build` or
`nix flake check` here uses them once accepted: answer Nix's prompt, or
pass `--accept-flake-config`. A flake that consumes this one
as an input must add them to its own `extra-substituters` and
`extra-trusted-public-keys`; Nix does not carry an input's settings
into the consumer.

## License

MIT, see [`LICENSE`](LICENSE).
