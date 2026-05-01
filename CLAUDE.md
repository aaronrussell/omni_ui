# CLAUDE.md

Guidance for Claude Code working in `omni_ui`. Architecture details
live in `context/design.md` — this file covers what to know as a
developer on this codebase and the conventions to follow.

## What this package is

`omni_ui` is a Phoenix LiveView component kit for building agent chat
interfaces on top of [`omni_agent`](https://github.com/aaronrussell/omni_agent).
Three layers — pick the entry point that matches how much control you
want:

```
OmniUI.AgentLive       — mountable LiveView. Header, sessions drawer,
                         artifacts panel, REPL+Artifacts tools, chat.
       │
use OmniUI             — macro. Adds session streaming, state, and
                         event handling to any LiveView.
       │
OmniUI.Components      — pure function components. Layer 1 building
                         blocks.
```

OmniUI does **not** own conversation state — `Omni.Session` (in
`omni_agent`) does. The LiveView subscribes to a session and mirrors
its state into assigns. There is no local tree-mutation path; all
writes go through `Omni.Session`.

For the full architecture (state ownership, event handling, branching
flow, artifacts, REPL, theming), read `context/design.md`.

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
- **Component → parent messages** use `{OmniUI, :event_name, ...}`
  tuples (e.g. `{OmniUI, :new_message, msg}`,
  `{OmniUI, :edit_message, turn_id, msg}`,
  `{OmniUI, :notify, notification}`). Subscribed-session events
  arrive as `{:session, pid, event, data}`. Manager events arrive as
  `{:manager, mod, event, data}`. Don't conflate the three.
- **`omni:` prefix on `phx-click` events** for events the macro
  routes through `OmniUI.Handlers.handle_event/3`. Bare event names
  belong to the consumer.
- **Match commit message style** of `git log --oneline`: imperative
  mood, ~50-char subject, terse body when needed. Sign with
  `AI-assisted commit (Claude)`.

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
- **`phoenix_live_view`** — real-time UI.
- **Tailwind 4** — styling via OKLCH semantic tokens defined in
  `priv/static/omni_ui.css`.
