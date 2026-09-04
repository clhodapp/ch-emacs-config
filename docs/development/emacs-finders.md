# Buffer, Window, and Frame Finders

How the Emacs config lets you *get to* a buffer, window, or frame:
the leader-key scheme, the type-to-find commands behind it, and the
semantic (embedding-based) finders. Status: all of it is implemented,
including the semantic finders (`semantic-finder.el` here, engine in
ch-local-llms).

## Motivation

Buffers, windows, and frames have three different retrieval shapes,
and the config should offer the right tool for each:

- **Buffers** are many, named, and searchable — a completing-read over
  names (`consult-buffer`) is the primary action, and content search
  covers the case where you remember what a buffer *contains* rather
  than what it is called.
- **Windows** are few and positional. They are normally addressed
  spatially (`w h/j/k/l`, `w w`), but with several frames on several
  monitors a type-to-find over "which window shows what" beats
  scanning screens by eye.
- **Frames** were previously reachable only via two commands squatting
  in the windows prefix (`w F` = `make-frame`, `w o` = `other-frame`)
  — the latter actively misleading, since under a windows prefix `o`
  reads as "only" (vim's `C-w o`). They now have their own prefix.

## Leader-key scheme

The double-press convention holds throughout: `<prefix> <prefix>` is
the domain's primary action (`b b` switch buffer, `f f` find file,
`w w` other window, `F F` other frame). Case pairs express
narrow/broad scope, mirroring `f f` (file at point) vs `f F` (find
file anywhere).

| Key | Command | Notes |
|---|---|---|
| `b b` | `consult-buffer` | primary buffer action |
| `b /` | `consult-line-multi` | literal content search across all buffers |
| `b f` | `find-buffer-by-description` | semantic content search (embeddings) |
| `w ?` | `find-window-by-description` | semantic, across frames; `?` = "ask by description" |
| `F ?` | `find-frame-by-description` | semantic; a frame ranks by its best window |
| `a /` | `claude-queue-find-agent` | semantic, over active background-agent conversations |
| `a ?` | `claude-queue-find-agent-all` | same, over the full `--all` history; shift = broader, as in the case pairs |
| `w f` | `find-window` | type-to-find a window in the current frame |
| `w F` | `find-window-anywhere` | same, across all frames; focuses the frame |
| `w o` | `delete-other-windows` | "only", as in vim's `C-w o` (was `other-frame`) |
| `F F` | `other-frame` | primary frame action (was `w o`) |
| `F f` | `select-frame-by-name` | type-to-find a frame (built-in) |
| `F n` | `make-frame` | was `w F` |
| `F r` | `set-frame-name` | name the current frame — feeds `F f` |
| `F d` / `F D` | `delete-frame` / `delete-other-frames` | |
| `t f` | `follow-mode` | moved from `w f`; it is a toggle |

There is deliberately no "find window by name" *within* the windows a
frame already shows you — `w f`'s value is real only once buffers and
frames carry discriminating names, which is the next section.

## What names a candidate

A finder is only as good as its candidate strings.

- **Buffers**: `uniquify-buffer-name-style` is set to `forward`, so
  same-named files disambiguate by leading path segments
  (`fleet/default.nix` vs `machines/default.nix`) instead of the stock
  `default.nix<2>`. Typed narrowing can then use directory words.
- **Windows**: windows have no names of their own; the finders
  synthesize candidates from the displayed buffer (plus a frame-name
  prefix in the across-frames variant, so narrowing by frame works),
  disambiguating duplicates with an index. The current window sorts
  last, so plain `RET` never re-selects where you already are.
- **Frames**: frames are unnamed by default, which makes
  `select-frame-by-name` useless out of the box. `F r`
  (`set-frame-name`) is the manual naming affordance; name a frame
  after its role ("mail", "nas work") and `F f` becomes a real
  finder.

## Content recall

Two layers, by what you remember:

1. **A literal fragment** — `b /` (`consult-line-multi`) greps the
   live contents of all open buffers. If any token of what you're
   looking for is verbatim in a buffer ("maxtries", a hostname, an
   error code), this finds it with zero infrastructure.
2. **A description of what was happening** — no literal token
   overlap. That is the semantic finder's job, below.

## Semantic finders

Retrieval by *description*: "the terminal where the build kept dying
on a hash mismatch" shares no substring with the scrollback that
matters. Embeddings absorb that vocabulary mismatch; nothing else in
the stack does. Implemented as the `semantic-finder` local package:
`find-buffer-by-description` (`b f`) plus window and frame variants
(`w ?`, `F ?` — `?` as the semantic sibling of the literal `/`
searches). Windows rank by the buffer they display, frames by their
best-matching window.

### Engine

`llama.cpp`'s `llama-server --embeddings` with a hash-pinned
`granite-embedding-english-r2` GGUF (149M ModernBERT, 8192-token
context, Apache 2.0, CLS pooling; mradermacher's Q8_0 conversion —
ibm-granite publishes no GGUF for the r2 embeddings), run as a
socket-activated home-manager user service from ch-local-llms
(`ch-local-llms.embedding-server`). Vulkan backend
(`pkgs.llama-cpp-vulkan`): GPU-vendor-neutral, no CUDA/ROCm closure.
Socket activation means nothing runs until the first query and the
server reaps itself after an idle timeout; the client sees only a
slow first response while the model loads.

The model choice is dominated by context length: it bounds how much
of a buffer one embedding can see, and terminal scrollback is exactly
the corpus where 512 tokens (granite r1) is hopeless and 8192 shines.
EmbeddingGemma-300m (2048 tokens, Gemma license, prompt-prefix
ceremony) was the runner-up.

Both sides of the asymmetric query/document pair get contextualizing
prefixes ("An emacs buffer named …, with the contents:" /
"An emacs buffer matching the description: "), so the model judges
"is this the buffer being described" rather than raw text similarity.
Oversize buffers contribute their head third and tail two-thirds —
the tail is where terminal activity lives, the head is where a file
declares what it is.

Rejected alternatives:

- **ollama** — a convenience wrapper around llama.cpp whose main added
  feature is an imperative, non-hash-pinned model store: a duplicate,
  worse path for artifact management the flake already owns.
- **vllm** — high-throughput batched serving for concurrent load;
  enterprise-shaped. A background labeler firing a few times a minute
  cannot use the throughput and still pays the closure and VRAM
  reservation.
- **hosted APIs** — terminal scrollback routinely contains secrets;
  buffer contents do not leave the machine. This is a boundary, not a
  preference.

### Index

`semantic-finder-index-mode` (enabled at startup) keeps an ephemeral
in-memory table of embeddings keyed by
`(buffer . buffer-chars-modified-tick)`:

- **Long tick with jitter**: the indexing cycle runs on a long period
  with a randomized start offset, and stale buffers are dripped
  through a queue on idle timers (one embed per few seconds) rather
  than batch-fired — no thundering herd after a burst of activity
  dirties many terminals, and no competition with typing.
- **Changed-buffers only**: each cycle diffs modification ticks
  against the table, so quiet sessions cost a no-op scan.
- The memo table is the single source of truth; the indexer is only a
  cache warmer. If it falls behind, queries degrade in freshness, not
  correctness.
- On machines without the embedding server, the first failed request
  backs the indexer off (`semantic-finder-backoff`), so the config
  stays portable to hosts that don't enable the service.

### Query path

Freshness is explicitly not critical — a terminal's last few thousand
lines describe "what was happening there" even if the newest hundred
are missing. So:

- The finder embeds the typed description and ranks buffers against
  whatever the table already holds — a pure lookup, no synchronous
  re-embed sweep.
- Buffers the indexer has never seen (just opened) are embedded on
  demand in one batched request, since a missing entry cannot rank at
  all.
- A `C-u` prefix forces a fresh sweep of stale buffers before
  ranking, for the "it just happened" case.

Scores are cosine similarities between boilerplate-subtracted
residuals: each side sheds an embedded *anchor* of its own bare
prefix (document prefix with an empty name / bare query prefix; two
extra embeds, cached). Raw CLS cosines share a large common component
fed by the contextualizing boilerplate, so buffers that are mostly
prefix-plus-name hub near *every* query (field-observed as a thin
misspelled-"spagetti" buffer ranking high everywhere) and scores
crowd into a 0.75–0.92 band. Corpus mean-centering — the first fix —
only relocated the problem: a *short* query is itself mostly
boilerplate, and its residual from the code-heavy document mean
points straight at the odd buffer out (field round 2: "elisp code"
retrieved the pasta buffer). Anchors cancel each side's boilerplate
exactly, are corpus-independent (a buffer's score cannot shift as
other buffers come and go), and leave true matches around 0.4–0.6
with non-matches near or below zero, so a weak top hit is legible as
such.

Results land in a `completing-read` sorted by similarity (identity
sorters, as in the window finders) with the score as an annotation;
plain `RET` takes the top hit.

### Other corpora: background agents

The scoring core is a small API (`semantic-finder-embed`,
`semantic-finder-clip`, `semantic-finder-rank` — anchors handled
inside) so other packages can rank their own corpora by description.
claude-queue's `claude-queue-find-agent` (`a /`, `a ?` = full
`--all` history) is the first
consumer: it embeds each background agent's session transcript (the
user and assistant turns of the conversation, clipped head-and-tail
like buffers) under its own prefix pair, ranks against the typed
description, and attaches to the pick. Embeddings cache per session
id keyed by the transcript file's size and mtime, so each query
re-embeds only agents that have talked since the last one — always
in one batched request, no background indexer.

### Deferred: generative labels

One-line LLM-written buffer labels (a second small `llama-server`
instance with an instruct model) would improve *browsing* candidates
in the finders, but retrieval-by-description does not need them and
label matching reintroduces the vocabulary-mismatch problem. Add only
if the bare `buffer-name @frame` candidates prove weak in practice.
