# ch-emacs-config

A declarative Emacs configuration: the editor, its packages and its
init as a [nemacs](https://github.com/clhodapp/nemacs) module, with
the fonts and the programs that start a daemon that survives generation
switches carried in the editor package, all built from Nix.

## What it provides

**Bundles.** Features are grouped rather than listed one package at a
time. Enabling the `eglot` bundle brings the language-server wiring, its
init, and the packages behind it; the same for `jinx` spell checking,
`consult-gh`, `render-dwim`, and the rest. A bundle is the unit you turn
on. Bundles are a nemacs option: the nemacs module `default` defines
this configuration's bundles, each on by default, and any other nemacs
module can turn a bundle off, append to its init, or add more bundles.

**A daemon with custody rules.** The systemd user unit is keyed by a
hash of the Emacs generation, so a new generation starts a new daemon
rather than leaving the old one serving stale code. A launcher starts
the unit when the generation it belongs to has none, and retires the
daemon that holds the socket: the socket is renamed, and that daemon is
told it is replaced and closes when its last frame does. A retired
daemon's exit must not delete the socket the new generation holds,
which is asserted by a check rather than hoped for: the exit unlink
happens through two paths, and an Emacs bump that renames either one
fails the build.

**Launchers that resolve at run time.** The editor package carries the
launchers (`emacsclient-desktop-launcher`, `emacsclient-editor-launcher`
and `ch-emacs-config-daemon-ensure`), so `nemacs switch` replaces them
together with the editor. The desktop entry and `$EDITOR` name them by
their path in the Nix profile of the editor, and each launcher finds
`emacs` and `emacsclient` beside itself when it runs. Desktop caches,
taskbar pins, and long-lived shells all capture what they saw at index
time and never notice a profile switch, so a launcher with baked paths
eventually drives a daemon that no longer exists.

**Pull request review.** `gh-review` opens a GitHub pull request in a
separate tab, laid out like GitHub's review page: a speedbar tree of
the changed files (or of every file), the diff as one card per file
with rows that expand the unchanged lines around a change, and the
conversation beside it. The file before, the file after, a whole-file
diff and an ediff are one key away from any file. `<leader> g v` opens
the pull request whose link is on the clipboard. Diffs and files are
read from a local cache repository holding the pull request's two
commits, so reading more context costs no API calls.

**Language servers from a shared table.** The eglot configuration
renders one table of servers, published on the composed library as
`ch-emacs-config.languageServers`, which any other LSP client
configured alongside this editor can read, so two clients on one
project cannot disagree about how to spawn a server.

**The programs it runs, closed over.** The init spawns more than
Emacs: git for magit and the vc backend, ripgrep for the project grep,
direnv for envrc, the GitHub CLI for consult-gh and gh-review, plantuml and graphviz
for diagram previews, merman for mermaid, and the language servers
above. The built init names every one of them by its Nix store path
(`lib-overlays/default/executables.nix` is the table), so
the editor behaves the same on a host that has none of them installed,
and the exported package is a working editor without anything else
installed. The fonts it names are carried in the editor package under
`share/fonts` (`lib-overlays/default/fonts.nix`), since a font resolves
by family through fontconfig. What the host still has to provide is
listed under [Host requirements](#host-requirements).

## Use it

A [caisson](https://github.com/nix-caisson/caisson) flake lists this
flake in `projects`, and the editor is a nemacs configuration declared
inside a home-manager configuration. The nemacs module `default` of
this flake configures it, and everything about the editor itself is set
in that nemacs configuration:

```nix
{
  # in a home-manager configuration that imports
  # ch-emacs-config.modules.homeManager.emacs:
  ch-emacs-config.emacs.enable = true;

  caisson.nemacs.configurations.editor = lib.caisson.nemacs.mkConfiguration {
    configModule = {
      package = pkgs.ch-emacs-config.emacs-pgtk;
      bundles.jinx.enable = false;
    };
  };
}
```

The home-manager configuration keeps the editor in a Nix profile of the
user, `$HOME/.local/state/caisson/profiles/nemacs/editor`, puts its
`bin` directory on `PATH`, and adds its `share/fonts` directory to
fontconfig. `nemacs switch` from the nemacs repository updates the
editor without activating the home-manager configuration. What the
home-manager module `emacs` adds is the desktop entry and `$EDITOR`,
which name the launchers in that profile, and the spell-check
dictionaries. `ch-emacs-config.emacs.configuration` names the nemacs
configuration that is the editor, `editor` by default.

Elsewhere, `modules.nemacs.default` is a nemacs module like any other,
for `nemacs.lib.nemacs.evalNemacs`.

The flake also exports the Emacs packages it validates against
(`emacs`, `emacs-pgtk`, `emacs-nox`) and an overlay carrying them.

To try the configuration without installing anything, run the
exported package; it carries the whole package set, the init, and
every program the init spawns:

```sh
nix run 'github:clhodapp/ch-emacs-config#emacs'
```

Each pinned program is an option of the nemacs module,
`ch-emacs-config.executables.<name>`
(`git`, `ripgrep`, `direnv`, `gh`, `plantuml`, `graphviz`, `merman`).
Set one to another package to substitute it, or to `null` to leave
that program to `PATH` at run time, in which case the host provides
it.

The fonts work the same way, as `ch-emacs-config.fonts.<name>`
(`default`, `symbols`, `emoji`, `emojiFallback`), with the table in
`lib-overlays/default/fonts.nix`. They cannot be pinned by
store path the way a program can, because Emacs resolves a font by
family through fontconfig, so the editor package carries each one and
the nemacs module emits the init lines naming it. Setting one to
`null` drops both halves: the package and the line naming its family,
leaving that font to the host. `ch-emacs-config.fontHeight` sets the `:height` of the
default face, which is worth revisiting when substituting the default
font, since families differ in how much of the em they fill.

## Host requirements

The pinned programs cover what the init runs itself. The host still
provides:

- A POSIX userland: coreutils, findutils, grep, sed, awk, and xargs.
  dired lists with `ls`, the grep and find fallbacks in consult and
  xref shell out to them, and Man-mode filters pages through sed and
  awk.
- `man` and its pages, for Man-mode and `consult-man`. A store-pinned
  `man` would not know the host's page directories.
- The login shell, which ghostel spawns from `$SHELL` (falling back to
  `/bin/sh`).
- `nix`, when an `.envrc` uses it: direnv is pinned, what the envrc
  invokes is not.
- The Rust toolchain of each Rust project. rust-analyzer is pinned, but
  it runs `cargo` and `rustc` from `PATH`, where envrc usually puts the
  toolchain of a dev shell. Formatting runs the rustfmt of that same
  toolchain.
- Spell-check dictionaries. jinx checks through enchant, which reads
  hunspell dictionaries from the enchant configuration directory; the
  Home Manager module provisions `en_US` there, the bare package does
  not.
- Any program whose `executables` option was set to `null`.

## Development

`nix flake check` builds both Emacs variants, boots each as a daemon and
probes init health over `emacsclient`, batch-loads the full init the way
real startup does, runs the ERT suites for the packages defined here,
and runs the launchers of the daemon against a stand-in for systemd. A
caisson consumer that declares the editor inside a home-manager
configuration is built as a check too, so the recipe above cannot rot.

`nix fmt` formats.

In CI the same `nix flake check` runs with the Nix store cached between
runs, since a cold runner native-compiles the whole Emacs package set
and takes most of an hour. A pull request that leaves `.github/` alone
is checked by `main`'s copy of the workflow, in `main`'s context after
the check of the pull request completes, and adds its build to the
shared cache. A pull request that changes the pipeline is checked by
the copy in the pull request, under a cache only that pull request can
see. The comments at the top of the workflow files say why that split is what makes the cache safe to write
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

The flake's `nixConfig` declares these substituters, so a direct `nix build` or
`nix flake check` here uses them once accepted: answer Nix's prompt, or
pass `--accept-flake-config`. A flake that consumes this one
as an input must add them to its `extra-substituters` and
`extra-trusted-public-keys`; Nix does not carry an input's settings
into the consumer.

## License

MIT, see [`LICENSE`](LICENSE).
