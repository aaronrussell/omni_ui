# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OmniUI is a LiveView component kit for building agent chat interfaces, powered by the `omni` Hex package. All three layers are built: function components (Layer 1), `use OmniUI` macro (Layer 2), and `AgentLive` (Layer 3). Artifacts system and code sandbox are complete.

- `context/roadmap.md` — Roadmap and upcoming workstreams
- `context/architecture.md` — Current architecture, data structures, and component hierarchy
- `.claude/skills/omni/SKILL.md` — Omni library API reference (use the `omni` skill when writing code that uses Omni)

## Project Structure

- **Root (`/`)** — The `omni_ui` library package. Core components live in `/lib/omni_ui/`. This is where all development happens.
- **`/omni_ui_dev/`** — Companion Phoenix app for testing the UI kit in a browser. Depends on the library via `{:omni_ui, path: "../"}`. You shouldn't need to work in here.
- **`/context/`** — Project context: `roadmap.md` (upcoming workstreams), `architecture.md` (current design).

## Commands

All commands run from the **project root**:

```bash
mix compile                  # Compile the library
mix test                     # Run tests
mix test path/to/test.exs    # Run a single test file
mix format --check-formatted # Check formatting
mix format                   # Auto-format code
```

## Architecture

**Three-layer component design** (see `context/architecture.md` for full details):

1. **Function Components** (Layer 1) — Pure rendering, no state. `components.ex` contains all function components.
2. **`use OmniUI` Macro** (Layer 2) — Injects streaming plumbing, state management, and init into any LiveView.
3. **`AgentLive`** (Layer 3) — Mountable LiveView built with the macro. Reference implementation with artifacts panel, tool wiring, and session management.

**Source of truth:** `OmniUI.Tree` (branching message history) is the app's authoritative store. The `Omni.Agent` is a downstream consumer — synced to the tree before each prompt. Turns are computed views over the tree, never stored.

**Component hierarchy:** `AgentLive` → `chat_interface/1` → stream of `TurnComponent` (LiveComponent) + `@current_turn` via `turn/1` (function component) + `EditorComponent` (LiveComponent) + `toolbar/1`.

**Streaming flow:** `Omni.Agent` → `{:agent, pid, type, data}` messages → `handle_info` → accumulates into `@current_turn` → on `:done`, pushes response messages to tree, builds completed turn with branching metadata, inserts into `:turns` stream.

**CSS theming:** `priv/static/omni_ui.css` — semantic OKLCH color tokens (`omni-bg`, `omni-text-1..4`, `omni-border-1..3`, `omni-accent-1..2`) with dark mode. Markdown typography scoped via `[&_.mdex_*]` descendant selectors.

## Key Dependencies

- **`omni`** — Unified LLM client (Anthropic, OpenAI, Google, etc.)
- **`phoenix_live_view`** — Real-time UI components
- **Tailwind CSS 4** — Styling via semantic color tokens defined in `priv/static/omni_ui.css`
