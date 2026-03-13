# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OmniUI is a LiveView component kit for building agent chat interfaces, powered by the `omni` Hex package. Currently in **Phase 1** — hand-wiring the core chat UI before extracting abstractions.

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
- `OmniUI.ChatLive` (LiveView) → `OmniUI.AgentInterface` (LiveComponent) → `OmniUI.Messages` (function components) + `OmniUI.MessageEditor` (LiveComponent)

**Streaming flow:** `Omni.Agent` GenServer → sends process messages → LiveView `handle_info` → updates assigns (`@current_message`, `@streaming`, `@messages`) → function components re-render.

**Key pattern:** `tool_result_map/2` pairs tool_use blocks with their results across messages at render time.

## Key Dependencies

- **`omni`** — Unified LLM client (Anthropic, OpenAI, Google, etc.)
- **`phoenix_live_view`** — Real-time UI components
- **Tailwind CSS 4 + daisyUI** — Styling (in the dev app)
