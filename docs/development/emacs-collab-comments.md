# Collaborative Comment Threads on Buffer Text

Review-style comment threads that the user and coding agents attach to
regions of live buffer text, layered on the Emacs MCP server
([`emacs-mcp-agent-tools.md`](emacs-mcp-agent-tools.md)). Status:
implemented. The threads themselves are the standalone Emacs package
[`collab-comments`](https://github.com/clhodapp/collab-comments)
(GPL-3.0-or-later, a plain package repository with no Nix in it); this
repo pulls it in and adds the user surface and the agent surface:

- `flake.nix` pins the package as the non-flake input `collab-comments`;
  `pkgs/emacs/collab-comments/package.nix` builds it into the Emacs
  package set through `pkgs/emacs/overrides.nix` (the same layer that
  pins `ghostel`), where every scope that builds the package set
  (`modules/home-manager/emacs/default.nix`, `lib/package-scope.nix`,
  `lib/package-manifest.nix`) receives the input's source in the
  `sources` attribute set (keyed by package name, one `package.nix` per
  entry under `pkgs/emacs/`).
- `inits/collab-comments.el` is the init bundle: leader keys, evil
  state for the thread view, auto-show on, restore-on-visit.
- `inits/mcp-server.el` holds the `add-comment`/`list-comments` MCP
  tools.
- `modules/home-manager/emacs/tests/collab-comments-ert.el` is the
  batch suite for this integration.

Bumping the package is `nix flake update collab-comments` in this repo
(the pin is an external input, so CI's weekly upstream cycle advances
it with `nixpkgs` and the rest; hand bumps cover the in-between).

## Motivation

Co-editing a shared buffer (drafts in `*agent/...*` buffers, code under
discussion) had exactly one channel: mutating the text. There was no way
to say *about* a passage "this is confusing" or "did you mean X?"
without either editing it or describing its location in chat. Comment
threads give both sides a margin to write in: anchored to the text they
discuss, visible in place, and strictly non-destructive — a comment
never changes the document.

## Model

The package README is the reference for the model; the facts this
integration depends on:

- A **thread** is an overlay over the annotated region carrying a
  session-unique integer id and a list of comments (author, timestamp,
  body). Overlays never alter buffer text.
- Anchor edges are inclusive on both sides (undo safety), and
  buffer-local change hooks re-find an anchor by its text after a
  wholesale replacement, so `replace-match` (the `edit-buffer` /
  `edit-file` verbs) and erase-and-reinsert (a `present` re-run under
  the same name, a transcript refresh) keep threads on their text
  instead of highlighting the whole insertion. A thread left spanning
  the entire document is folded to an empty anchor at its end.
- Threads on **buffers with a document key are persisted**: file
  buffers (key = file truename) and buffers whose owning mode declares
  the buffer-local `collab-comments-document-key` (claude-queue
  transcript views — see Conversation surfaces). Undeclared non-file
  buffers (`*agent/…*` co-drafts) are session-scoped.
- A thread whose anchor text is deleted survives and renders as
  `(anchor text deleted)`.

## User surface

Leader prefix `SPC k` ("comments"), motion state:

| Key | Command | Does |
|---|---|---|
| `k a` | `collab-comments-add` | new thread on region (or current line) |
| `k r` | `collab-comments-reply` | append to thread at point (else starts a thread here — typed text is never dropped) |
| `k k` | `collab-comments-show` | thread view, focused on point's thread |
| `k b` | `collab-comments-browse` | completing-read jump to a thread |
| `k n` / `k p` | next/previous | cycle thread anchors, echoing the thread |
| `k d` | `collab-comments-dismiss` | delete thread at point (else pick) |
| `k D` | `collab-comments-dismiss-all` | delete all threads here (confirms) |
| `k h` | `collab-comments-toggle-hidden` | hide/show decorations |
| `k t` | `collab-comments-auto-show-mode` | toggle echo-at-point (on by default) |
| `k g` | `collab-comments-restore` | re-anchor this file's threads from the store |

**Auto-show** (`collab-comments-auto-show-mode`, global, enabled by the
init): moving point onto commented text shows the thread(s) through
eldoc — a doc function registered buffer-locally ahead of the
LSP/flymake ones, so inside commented text the thread outranks hover
and code-action hints. When the thread view is visible the echo yields
and the view window follows point instead; moving between sections in
the view points the source window at the matching anchor.

The **thread view** (`*comments: <buffer>*`, a `special-mode` list
opened in evil motion state) lists every thread in position order, with
`n`/`p` between threads, `RET` visiting the anchor, `r` reply, `d`
dismiss, `D` dismiss all, `g` revert, `q` quit. Any mutation from either
side re-renders a live view, so it doubles as a live feed of the
agent's comments.

## Persistence

The store (`collab-comments-store-file`, one Lisp-data file under
`user-emacs-directory`) is written through on every thread mutation
and refreshed at the save and auto-save checkpoints; restoration
compares a stored content hash against the buffer and re-finds anchors
by text when it differs (details in the package README).

The init wires restoration on `find-file-hook` behind a cheap
store-existence guard (the literal file name pairs with
`collab-comments-store-file`), keeping the package lazy for ordinary
file visits. The package itself restores after revert and
`recover-this-file`; claude-queue restores after each transcript
re-render.

## Agent surface (MCP tools)

- **`add-comment (text, file?|buffer?, anchor?, thread?)`** — with
  `anchor`, starts a new thread: the anchor is literal text matched
  under the `edit` tool's contract (must occur exactly once, ambiguity
  errors with the count), so a stale anchor fails loudly instead of
  annotating the wrong text. With `thread`, appends to that id.
  Author is always `claude`. Returns the rendered thread.
- **`list-comments (file?|buffer?)`** (read-only) — threads with ids,
  `buffer:line` positions, anchor excerpts, and full bodies; the
  unfiltered form sweeps all buffers. This is how the agent reads the
  user's comments and finds thread ids to reply to.

Statefulness: `add-comment` mutates only overlay state, never text —
it sits with `present` in the mildly-stateful-by-design class of the
`live-emacs-safety` policy, consented once here at design time.

## Decisions

- **Edit-contract anchors.** The agent addresses text the same way its
  native Edit tool does — a unique literal string — riding trained
  instincts instead of inventing positions-by-line that drift under
  concurrent editing.
- **A plain package, pinned as a non-flake input.** The package repo
  carries no Nix, so it is consumed as source (`flake = false`) and
  built here with `melpaBuild`; the version is derived from the pinned
  commit's date. A flake input rather than a `fetchFromGitHub` pin so the
  weekly upstream cycle advances it and no hash is maintained by hand.
- **No new dependencies.** Plain overlays, `completing-read` (vertico
  serves it), and a `special-mode` list; no posframe/transient.

## Testing

`checks.<system>.emacs-collab-comments-ert` runs the integration suite
against the full init: the two MCP tools (anchor uniqueness contract,
argument validation, file targets), and thread survival across a
`present` re-run followed by `edit-buffer` and across a claude-queue
transcript re-render. Registration (schema validation) is covered by
`emacs-mcp-tools-ert`. The package's own suite (model, anchors under
replacement, thread view, persistence; `make test` under `emacs -Q`)
runs in its repository's CI.

## Conversation surfaces

Comment threads on Claude conversation views — saying "did you mean X?"
about a turn of a session the way one already can about a passage of
code. The surface is claude-queue's transcript view
(`claude-queue-open`'s rendered buffer): a plain text document, so the
anchor contract works on it unchanged. Terminal views (ghostel attach
buffers) are out of scope — libghostty's projection of the TUI's
screen has no stable content identity to anchor to.

The re-anchor machinery reaches transcripts through the document key.
`claude-queue--show-text` keys the view
to `claude-session:<session-id>` (the transcript file's base name —
durable across renders, Emacs restarts, and the session's directory
moves) and invokes the restore path after each erase-and-reinsert
refresh, exactly as `after-revert-hook` does for files. The re-anchor
machinery fits as-is: transcripts render deterministically and
append-mostly, so the content-hash fast path and the
unique-occurrence / nearest-position fallbacks hold. Persistence
across Emacs restarts falls out of the written-through store.

The document key is also the persistence face of the buffer-metadata
declaration in the workspace consent-gate design: the owning mode
declares what the buffer renders (this session) and what comments on
it mean (margin notes on the conversation).
