# Emacs MCP Server: Agent Tools Design

Design for extending the Emacs MCP server
(`modules/home-manager/emacs/inits/mcp-server.el`) beyond its initial four
tools (`eval-elisp`, `context`, `list-buffers`, `buffer-text`) into a tool
set that gives coding agents real leverage from the live Emacs session.
Status: implemented — `mcp-server.el` plus the batch smoke suite
`modules/home-manager/emacs/tests/mcp-tools-ert.el`.

## Motivation

A coding agent already has grep, ranged file reads, shell, and a native
edit tool. Mirroring those through Emacs adds nothing but token cost and
permission friction. What the agent *cannot* get anywhere else is what the
live session uniquely holds:

1. **Warm LSP servers** — eglot already runs ruff/ty, nixd, ts-ls, etc.
   with correct per-project configuration and envrc/direnv environments.
   Semantic answers (references, types, diagnostics) come from servers
   whose setup problem is already solved.
2. **Unsaved buffer state** — the classic agent/user conflict is the agent
   editing a file on disk while the user holds unsaved changes to it.
3. **User attention** — where the user is, what they've selected, what is
   red on their screen right now.
4. **The editing engine** — for bulk/structural edits, one short elisp
   form beats N native old-string/new-string edits or a structure-blind
   sed.

Plus one channel in the other direction: the agent presenting rich,
navigable context *to* the user inside Emacs, instead of cramming it into
terminal question prompts.

## Design principles

- **Session-unique only.** Every tool must answer a question only the live
  session can answer, or serve the agent↔user coordination/presentation
  channel. Anything the agent's native tools do well is out (one canonical
  path; no convenience aliases).
- **Ride the agent's training priors.** Agents do not practice: they start
  every session with the same baked-in fluency and never get better at a
  bespoke interface. So interfaces reuse what is already deeply trained:
  positions in (`file`, `line`, `col`), grep-format lines out
  (`path:line:col: text`), vanilla elisp idiom for the escape hatches.
  Never keystroke sequences, never a custom query DSL.
- **Fast, legible feedback substitutes for practice.** Where a tool
  mutates something, it returns evidence (a unified diff), so the agent
  can correct in-session instead of compounding a fumble.
- **Read-only by default; statefulness explicit and bounded.** Tools are
  registered `:read-only t` wherever true. The stateful ones are
  enumerated below and their footprint is a deliberate policy decision,
  consented to once at design time (see the `live-emacs-safety` skill,
  which must be updated alongside implementation).
- **Token budgets everywhere.** Inline results are capped with total
  counts; the always-loaded guidance surface stays near zero (see Context
  budget).

## v1 tool inventory

Nine new tools plus two enhancements, stratified by confidence.

### High confidence (the reasons to build)

- **`diagnostics (file?)`** — current errors/warnings as
  `path:line:col: severity: message`; project-wide when `file` is omitted.
  Backed by `flymake-diagnostics` (eglot drives flymake natively; the
  config carries no other diagnostic frontend). Must distinguish "no errors"
  from "not yet checked". Fidelity caveat: diagnostics reflect *buffers*;
  after an agent edits on disk, the answer is only current if the buffer
  reverted — unmodified buffers are auto-reverted as part of the tool's
  buffer resolution, otherwise the tool quietly lies.
- **`find-references (file, line, col)`** and
  **`find-definition (file, line, col)`** — xref/LSP-backed, grep-format
  output, capped with total count. Precise where grep gives false
  positives and missed indirections. For elisp buffers the native elisp
  xref backend serves; no eglot needed.
- **`modified-buffers ()`** — file-visiting buffers whose content differs
  from disk. The don't-clobber-the-user check; cheap enough to call before
  any edit in the user's active project.
- **`buffer-diff (file)`** — unified diff of buffer vs disk, so the agent
  can incorporate the user's in-flight edits instead of fighting them.
- **`context` (enhanced)** — existing tool, add: project root
  (project.el), current defun (`which-function`), active region text,
  modified-state of visible buffers.
- **`present (name, content, mode?, display?)`** — write a user-facing
  artifact into buffer `*agent/<name>*` and optionally display it.
  Default `markdown-mode` with `visual-line-mode` (prose is written as
  long lines and soft-wrapped to the window); `diff-mode` for proposed changes; a
  `compilation-minor-mode` treatment for evidence lists so `file:line:col`
  references are clickable jumps. Display via `display-buffer` without
  stealing focus, so `display-buffer-alist` governs placement. Intended pattern:
  before asking the user a non-trivial question, present the full context
  (options, tradeoffs, evidence) as a brief buffer, then ask with terse
  labels referencing it. Also serves "here's what I found, organized".
  `mermaid` mode renders diagram source via an mmdc-compatible CLI
  (`ch-emacs-config-mcp-mermaid-command`; the home-manager module bakes
  in the nix-installed merman, and the bare `mmdc` default only works
  when one is on PATH) and shows the SVG as an image (raw SVG text where
  images can't render) — the conduit models never had for the diagrams
  they habitually draft in plans.
  Theme follows the frame's background mode; a timeout guards the
  session against a hung renderer; render errors return the renderer's
  message so the agent can fix its source; a failed render never wipes
  the existing buffer.
- **`sidebar (name, content, display?)`** — read-once markdown beside
  the user's work: anticipated questions with answers, a glossary, a
  checklist. Buffer `*agent/sidebar/<name>*`, `markdown-ts-mode` with
  `visual-line-mode`, read-only, shown in a side window on the frame's
  right edge at `ch-emacs-config-mcp-sidebar-width` (0.2) of the frame;
  `q` closes the window and kills the buffer like a help viewer (bound
  in the minor mode and, under evil, in normal state). Distinct from
  `present` on purpose: `present` makes an artifact the user keeps and
  places by their own `display-buffer-alist`; a sidebar is disposable
  and always lands in the same place, so the output style that asks
  for one needs no placement instructions.

### Moderate confidence (cheap to carry)

- **`symbol-info (file, line, col)`** — LSP hover: type signature + docs.
  Big for the ruff/ty Python stack and nix.
- **`document-outline (file)`** — imenu / LSP documentSymbol tree; orients
  in a 3k-line file without reading it all. Works in every mode including
  the tree-sitter ones.
- **`buffer-text` (enhanced)** — optional `start-line`/`end-line` for
  paging large buffers, and `numbered=yes` to prefix absolute line
  numbers in the agent's native Read format (for answers that feed
  line-addressed tools).

### Build, but don't push (trigger lives in the skill only)

- **`transform (file, elisp, save?)`** — run an elisp form with the
  buffer current, then return a **unified diff of what changed**. This is
  the editing engine's paved path: computed multiline replacements
  (`query-replace-regexp` with `\,(elisp)`), sexp-aware transforms
  (wrap/raise/splice over balanced expressions — this workspace is elisp
  and nix, both nesting-heavy), mode-canonical `indent-region`, and
  wgrep-style transform-across-matches. One 60-character form replacing
  40 native edits is the case where the elisp tax inverts. Guardrails:
  refuses buffers with unsaved user modifications; the diff return is the
  verification step. Honest expectation: rare-but-valuable use — agents
  reach for native edits by habit, and pushing this tool in always-loaded
  context is the wrong spend. `eval-elisp` remains the escape hatch, not
  the editing interface.

- **`edit-buffer (old-string, new-string, buffer, replace-all?)` /
  `edit-file (old-string, new-string, file, replace-all?)`** — single
  literal string replacement with the agent's **native Edit contract**:
  the old string must match exactly once (an error naming the count
  otherwise; `replace-all` opts out), must differ from the new string,
  and matching is literal, never regex. Rationale: the agent's editing
  instincts are trained against exactly these semantics, and the
  uniqueness rule doubles as optimistic-concurrency protection when the
  target is a buffer the user is editing live — a stale anchor fails
  loudly instead of editing the wrong occurrence (first observed
  hand-rolling `search-forward` transactions during live co-editing,
  where first-match semantics silently lack that guarantee). Beyond the
  native contract both verbs return the unified diff. They are two tool
  names, not one tool with a target parameter, because the boundary
  between them is a capability boundary: a dispatch profile can deny
  `edit-file` by name and the deny floor holds structurally (workspace
  `consent-gate.md`; claude-queue does so for dispatches rooted
  outside any project, where the territory would be a bare directory). `edit-buffer` mutates a live buffer
  and never writes disk — non-file buffers (the `*agent/...*`
  co-editing case) are edited in place; a file-visiting buffer is left
  modified as a staged edit, so unsaved user modifications are workable
  state for it, with the uniqueness rule as the drift guard. `edit-file`
  edits the file's buffer and always saves; it refuses buffers holding
  unsaved user modifications (like `transform`) — that disk write
  escalates to the resident side instead. `transform` remains the tool
  for 3+ edits or structural work; the edit verbs replace the
  eval-elisp shim for the single surgical change.

- **`add-comment` / `list-comments`** — review-style comment threads on
  buffer text, shared with the user; anchors follow the edit verbs'
  unique-literal contract. Designed separately in
  [`emacs-collab-comments.md`](emacs-collab-comments.md).

## Interface conventions

- Positions in: `file` (absolute path), `line`, `col` — matching how
  agents already consume grep output.
- Locations out: `path:line:col: text` lines, grep conventions.
- Inline results capped (per-tool `limit` with a sensible default),
  always accompanied by the true total count.
- Plain text throughout; no elisp needed on any common path.

## Implementation notes

- **Buffer resolution.** Semantic tools need the file in a live buffer
  with eglot attached. Resolution order: existing buffer (auto-revert if
  unmodified), else `find-file-noselect` — which is mildly stateful
  (opens a buffer, boots LSP via the `eglot-ensure` hooks) and is the
  accepted footprint of these tools.
- **Auto-open scope is a policy knob**: `session-projects-only` (default)
  vs `any-project`. The wide setting lets the live daemon host eglot
  sessions for agent worktree checkouts as ordinary multi-project use —
  the heavy resources (ty indexing, nixd evals) live in language-server
  subprocesses either way; the marginal session cost is buffers plus a
  jsonrpc connection. Wide mode owes one piece of hygiene: shut down
  eglot sessions and kill buffers whose project root vanished (worktrees
  get auto-cleaned). Ship narrow, widen after living with it.
- **Synchronous LSP.** Tool handlers return synchronously: use
  `jsonrpc-request` against `(eglot--current-server-or-lose)`, not the
  async xref UI paths.
- **Timeouts.** Every LSP call runs inside the user's interactive session;
  wrap in `with-timeout` (a few seconds) so a hung server degrades to a
  tool error instead of freezing both Emacs and the MCP bridge.
- **Diagnostics freshness.** Report "not yet checked" rather than a
  misleading empty list; auto-revert unmodified buffers before reading.
- **After `transform`.** The agent harness requires re-reading a file
  changed outside its own edit tools before further native edits — a
  known step, not a problem; note it in the skill.

## Context budget (where the guidance lives)

Cross-session improvement is real but paid for in context. Three tiers:

1. **Always-loaded** (tool descriptions + server `:instructions`):
   one-line triggers only — "3+ similar edits → transform",
   "type/callers question → semantic tools", "before editing in the
   user's active project → modified-buffers", "before asking a
   non-trivial question → present". Schemas are context too: few
   parameters per tool, terse descriptions.
2. **Loaded on trigger**: an `emacs-tools` usage skill (peer of
   `live-emacs-safety`) holding the depth — transform recipes, the
   auto-open policy, the present-before-asking pattern, gotchas. Costs
   one line per session when unused. The skill's source lives at
   `modules/home-manager/emacs/skills/emacs-tools/` and is installed
   into `~/.claude/skills/` by the emacs home-manager module (with the
   mcp-server bundle) through the claude-code module's merged `skills`
   option — edit it there and rebuild, not in place.
3. **Loaded on recall**: agent memories for corrections and discovered
   patterns; one index line each.

Promotion discipline: lessons land in memories, get promoted to the skill
when they prove general, and graduate to an always-on line only when every
session needs them — and each promotion to tier 1 should evict something.

## Safety

Statefulness classification (update `live-emacs-safety` to match):

- **Read-only**: `diagnostics`, `find-references`, `find-definition`,
  `symbol-info`, `document-outline`, `modified-buffers`, `buffer-diff`,
  `context`, `buffer-text`, `list-buffers`.
- **Mildly stateful by design** (consented at design time): auto-open of
  buffers within the configured scope; `present` writes an `*agent/*`
  buffer and may display a window (placed via `display-buffer-alist`, no
  focus steal).
- **Stateful with guardrails**: `edit-buffer` mutates live buffers
  (diff return, unique-match contract, never writes disk); `transform`
  and `edit-file` write files (diff return, dirty-buffer refusal). The
  disk-writing pair is what a dispatch profile denies by name when it
  withholds disk writing (workspace `consent-gate.md`); claude-queue's
  default profile allows both, relying on the filters below, and
  denies them, together with the CLI's own Edit/Write, only for
  dispatches rooted outside any project. All three are confined to
  the calling client's territory (next section).
- **Gated escape hatch**: `eval-elisp` accepts only elisp the
  agent-safe gate (next section) proves free of side effects — a
  read-only escape hatch. The `unrestricted` scope knob is the
  resident user's say-so path (`live-emacs-safety`) for stateful
  co-driving.

## Security filters

Two server-side filters (design context: workspace
`consent-gate.md`). The MCP server is a side-channel around the CLI's
permission machinery — no permission mode, sandbox, or hook matcher
sees a server-side write — so the filters live in the server, where
every client passes, including sessions no dispatch profile shaped.

- **Client-territory write scope.** Each request reaches Emacs
  through emacsclient, which binds `default-directory` to the stdio
  bridge process's cwd — the client session's launch directory
  (verified against live bridges; per-request, so concurrent clients
  never mix). The territory is that directory's project root
  (project.el), or the directory itself outside any project. The
  write verbs — `edit-file`, `transform`, and `edit-buffer` on
  file-backed buffers — refuse targets outside it. Containment is by
  path under that single root, not project identity: a workspace
  client reaches nested submodule checkouts and `.claude/worktrees/`
  trees (separate projects in Emacs's eyes), while a client launched
  inside a worktree or submodule checkout is confined to it —
  worktree isolation holds against the main checkout. Auto-open
  accepts in-territory files unconditionally (the agent-worktree
  case), and `present` refuses a file-visiting buffer squatting on an
  `*agent/…*` name rather than erasing it. Knob:
  `ch-emacs-config-mcp-write-scope` (`client-project` default,
  `unrestricted`). Comments (`add-comment`) are overlays, never text
  writes, and stay unfiltered.
- **The agent-safe elisp gate.** `eval-elisp` and `transform` parse
  their elisp and reject, before evaluation, any form `unsafep`
  cannot prove harmless. The metadata base is Emacs's own (`pure`,
  `side-effect-free`, `safe-function`), extended by two registries:
  `ch-emacs-config-mcp-agent-safe-functions` (innocuous but unmarked
  functions; seeds `error` and `ignore`) and, for `transform` only,
  `ch-emacs-config-mcp-agent-safe-editing-functions` — motion,
  search, and current-buffer mutation, enough for the transform
  recipes with no path out of the buffer: no `set-buffer`, no kill
  ring (clipboard), no `replace-regexp` family (their replacement
  strings evaluate embedded `\,(...)` elisp, which would bypass the
  gate). Gated code cannot reopen the gate: the knobs and registries
  carry `risky-local-variable`, which `unsafep` refuses to bind, and
  assignment to globals is refused wholesale. Knob:
  `ch-emacs-config-mcp-elisp-scope` (`agent-safe` default,
  `unrestricted`).

Residual accepted surface: reads can still carry session state out
(that is the tools' purpose); `sleep-for` and unbounded loops can
stall the session until `C-g` (already true of every synchronous
tool); same-user boundaries stay soft. This is accident-surface
hardening in consent-gate.md's sense, not an adversarial sandbox.

## Considered and rejected / deferred

Recorded so the reasoning survives; several of these look attractive and
were cut deliberately.

- **General search through Emacs (buffer-based rg) + a result buffer
  with pre/post-elisp params.** Native `rg > file` + ranged reads
  + refining greps already gives the persist/page/refine loop with
  cheaper, native tools; buffer-based search additionally blocks the
  user's UI. The unique residues were kept: `present` for showing results,
  and (deferred) buffer materialization as LSP-overflow handling.
- **`write-buffer` agent memory in buffers.** Disk files win: they
  survive Emacs restarts and are read with the agent's native tooling.
  Buffers only beat files when the content originates in Emacs or the
  audience is the user. Also: agents cannot trigger compaction (only the
  user can, via `/compact`), so eviction is passive either way and the
  pattern's value is all on the retrieval side — where files are better.
- **`workspace-symbols`.** Grep covers it; not worth the schema tokens.
- **`search-buffers` (multi-occur over unsaved content).** Redundant once
  `modified-buffers` + `buffer-diff` exist.
- **LSP rename / call hierarchy.** Rename mutates buffers project-wide
  and collides with the agent's own edit tool; revisit if `transform`
  proves itself.
- **Direct LSP↔MCP bridge (mcp-language-server et al.).** A second,
  parallel LSP config surface to keep in sync forever — and in this
  nix/envrc-heavy environment the per-project server/env setup is exactly
  the hard part eglot already solves. Worse failure mode: a disk-state
  bridge can contradict what the user's screen shows. The tool interface
  designed here (positions in, refs out) is backend-agnostic if headless
  use ever dominates.
- **Scratch Emacs daemon per worktree.** A better direct bridge — same
  nix-built config by construction, no consent issues, and the stdio
  bridge already reaches Emacs through an emacsclient socket, so the
  target socket is the connection point this design keeps open for it.
  Deferred: LSP cold start dominates
  short jobs, and daemon lifecycle is machinery that rots unused. The
  auto-open `any-project` knob covers worktree queries in the meantime.
- **Buffer materialization for oversized semantic results +
  `post-elisp`.** Cap-plus-total-count until it demonstrably hurts.
- **Keystroke-macro interfaces.** Compact for humans, permanently shaky
  for agents; elisp forms are the trained idiom.

## Rollout

1. Implement in `mcp-server.el` (or split a `mcp-server-tools.el`);
   register in the existing `mcp-server-lib-register-server` call; keep
   `:instructions` to trigger lines.
2. Write the `emacs-tools` skill; update `live-emacs-safety`.
3. Smoke tests in the existing harness (registration + non-LSP tools in
   batch; LSP-backed tools at least get a "no server → clean tool error"
   test).
4. Land, converge, HM switch + Emacs restart (as with the original MCP
   landing).
5. Live-verify against the running session (`diagnostics` and
   `find-references` on a real project are the acceptance test), then
   observe usage for a few weeks and prune what the agent never reaches
   for.
