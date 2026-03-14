# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OmniUI is a LiveView component kit for building agent chat interfaces, powered by the `omni` Hex package. Currently transitioning from **Phase 1** (hand-wired chat UI) to **Phase 2** (extracting `use OmniUI` macro).

- `context/vision.md` — Full architecture plan and phased roadmap
- `.claude/skills/omni/SKILL.md` — Omni library API reference (use the `omni` skill when writing code that uses Omni)

## Project Structure

- **Root (`/`)** — The `omni_ui` library package. Core components live in `/lib/omni_ui/`. This is where all development happens.
- **`/omni_ui_dev/`** — Companion Phoenix app for testing the UI kit in a browser. Depends on the library via `{:omni_ui, path: "../"}`. You shouldn't need to work in here.
- **`/context/`** — Additional project context files. Currently has the vision doc; more will be added over time.

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

**Three-layer component design** (vision — not all layers exist yet):

1. **Function Components** (Layer 1) — Pure rendering, no state. `messages.ex` contains message rendering functions. These are the hackable building blocks.
2. **`use OmniUI` Macro** (Layer 2, future) — Will inject streaming `handle_info` clauses, state management, and init into any LiveView.
3. **`ChatLive`** (Layer 3) — Mountable LiveView. The "just give me a chat" entry point.

**Current component hierarchy:**
- `OmniUI.ChatLive` (LiveView) → `agent_interface/1` (function component) → `OmniUI.Messages` (function components) + `OmniUI.MessageEditor` (LiveComponent)

**Streaming flow:** `Omni.Agent` GenServer → sends `{:agent, pid, type, data}` process messages → LiveView `handle_info` → builds up `@streaming_message` from deltas → on `:done`, pushes completed message onto `@messages` → function components re-render.

**Message shape:** The LiveView maintains its own `@messages` list (plain maps), separate from the agent's internal context. Each agent prompt round collapses into a single assistant message with accumulated content blocks and a `tool_results` map. See `context/vision.md` "Phase 1 Learnings" for details.

## Key Dependencies

- **`omni`** — Unified LLM client (Anthropic, OpenAI, Google, etc.)
- **`phoenix_live_view`** — Real-time UI components
- **Tailwind CSS 4 + daisyUI** — Styling (in the dev app)
