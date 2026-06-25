# CLAUDE.md

Guidance for Claude Code working in `omni_ui`. Architecture details
live in `context/design.md` — this file covers what to know as a
developer on this codebase and the conventions to follow.

## What this package is

`omni_ui` is a Phoenix LiveView component kit for building agent chat
interfaces on top of [`omni_agent`](https://github.com/aaronrussell/omni_agent).
Two ways to work:

- **`Omni.UI.AgentLive`** — batteries-included LiveView. Mount it
  and you have a working agent chat with sessions, files, REPL, and
  web tools.
- **`use Omni.UI`** — macro that injects session streaming, state,
  and event handling into your own LiveView. Compose with `ChatUI`
  and `CoreUI` components for the rendering layer.

Omni.UI does **not** own conversation state — `Omni.Session` (in
`omni_agent`) does. The LiveView subscribes to a session and mirrors
its state into assigns. There is no local tree-mutation path; all
writes go through `Omni.Session`.

For the full architecture (state ownership, event handling, branching
flow, files, REPL, theming), read `context/design.md`.

## Project structure

- **Root (`/`)** — the `omni_ui` library package. All development
  happens here.
- **`omni_ui_dev/`** — companion Phoenix app for testing the kit in
  a browser. Depends on the library via `{:omni_ui, path: "../"}`.
  You shouldn't need to work in here unless wiring changes.
- **`context/`** — `design.md` (architecture), `roadmap.md` (open
  work).
- **`.claude/skills/omni/`** — Omni library API reference. Use the
  `omni` skill when writing code that uses `Omni.*` (model selection,
  context, content blocks, message structs, the streaming API).

## Build & test commands

Run from the **project root**, not `omni_ui_dev/`. Mix resolves both.

```bash
mix compile                     # Compile
mix test                        # Run all tests
mix test path/to/test.exs       # Single file
mix test path/to/test.exs:42    # Single test by line
mix format --check-formatted    # CI formatting check (use this)
mix format                      # Auto-format
```

## Dev conventions

- **Don't start the dev server.** The user runs `cd omni_ui_dev && mix
  phx.server` manually and reports back. Compiling, testing, and
  format-checking are fine without permission.
- **Verify formatting with `--check-formatted`.** Don't blindly run
  `mix format` — formatting drift is information.
- **No emojis** in code, docs, or commit messages.
- **No comments unless they explain a non-obvious *why*.** Don't
  describe what well-named code already says. Don't reference the
  current task or PR — those belong in the commit message.
- **Event naming conventions:**
  - **`omni:`-prefixed** browser events are macro-routed through
    `Omni.UI.Handlers.handle_event/3` — the namespace prevents
    collision with consumer events.
  - **Bare verb_noun** events belong to AgentLive (cross-scope, so
    the noun disambiguates): `open_session`, `open_file`, `new_session`.
  - **Bare verb** events belong to LiveComponents (`phx-target={@myself}`),
    where the component is the implicit noun: `open`, `close`, `toggle`,
    `edit`, `submit`. Exception: keep the noun when the component has
    multiple things the verb could apply to (e.g. `cancel_upload`).
  - **Generic events** (`omni:select`, `toggle`) use a `"name"` param
    to distinguish targets rather than separate event names per target.
  - **JS dispatch events** use hyphens (web convention):
    `omni:before-update`, `omni:focus`. **Elixir events** use
    underscores: `omni:select`, `cancel_upload`.
  - **Process messages** routed by the macro use `{Omni.UI, :verb, ...}`
    tuples (e.g. `{Omni.UI, :new_message, msg}`,
    `{Omni.UI, :edit_message, turn_id, msg}`,
    `{Omni.UI, :notify, notification}`). AgentLive-only messages use
    bare atoms (e.g. `:active_session_deleted`).
  - **Session events** arrive as `{:session, pid, event, data}`.
    **Manager events** arrive as `{:manager, mod, event, data}`.
    Don't conflate the three message envelopes.
- **Path variable naming:** `*_dir` for directory paths, `*_file`
  for file paths, `*_path` only for generic filesystem paths or
  non-filesystem concepts (e.g. URL paths). This convention applies
  across all omni packages.
- **Match commit message style** of `git log --oneline`: imperative
  mood, ~50-char subject, terse body when needed. Sign with
  `AI-assisted commit (Claude)`.

## Documentation

- All public modules must have a `@moduledoc`. Internal/private
  modules use `@moduledoc false`.
- All public types must have a `@typedoc`. Keep it on one line
  unless complex.
- All public functions must have a `@doc` and a `@spec`. Rely on
  `@spec` for types — don't repeat in prose.
- Function components must have a `@doc` that says what the
  component renders and when to reach for it. `@spec` is not
  needed — `attr`/`slot` declarations replace it.
- LiveComponent `render/1` must declare `attr` and `slot` for its
  interface — they provide compile-time validation at call sites
  and generate documentation. `@doc` on `render/1` is not needed;
  the `@moduledoc` covers intent.
- Other LiveComponent callbacks (`mount/1`, `update/2`,
  `handle_event/3`) do not need `@doc` — they are implementation,
  not public API.
- Add inline `doc:` on `attr` and `slot` declarations when the
  name alone is ambiguous or the accepted values need explanation.
  Skip it when the name is self-evident.
- Document options when a function accepts them.
- Private functions (`defp`) do not need `@doc` annotations.
- Tone: practical, concise, example-driven. Lead with what you do,
  not what things are.

## Reference docs

- `context/design.md` — architecture, data flow, design decisions
- `context/roadmap.md` — open polish/release work
- `.claude/skills/omni/SKILL.md` — Omni library API
- `../omni_agent/context/design.md` — Session/Manager/Store/Agent
  mechanics

## Key dependencies

- **`omni`** — stateless LLM client (Anthropic, OpenAI, Google,
  OpenRouter, OpenCode, Ollama).
- **`omni_agent`** — `Omni.Agent`, `Omni.Session`, `Omni.Session.Manager`,
  `Omni.Session.Store`. Path dep at `../omni_agent` during development.
- **`omni_tools`** — `Omni.Tools.Files`, `Omni.Tools.Repl`,
  `Omni.Tools.WebFetch`. AgentLive's default agent wires these in.
  Path dep at `../omni_tools` during development.
- **`phoenix_live_view`** — real-time UI.
- **Tailwind 4** — styling via OKLCH semantic tokens defined in
  `priv/static/omni_ui.css`.
