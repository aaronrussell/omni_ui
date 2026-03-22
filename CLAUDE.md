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

1. **Function Components** (Layer 1) — Pure rendering, no state. `components.ex` contains all function components. These are the hackable building blocks.
2. **`use OmniUI` Macro** (Layer 2, future) — Will inject streaming `handle_info` clauses, state management, and init into any LiveView.
3. **`AgentLive`** (Layer 3) — Mountable LiveView. The "just give me a chat" entry point.

**Current component hierarchy:**
- `OmniUI.AgentLive` (LiveView) → `chat_interface/1` (function component) → `OmniUI.Components` (function components) + `OmniUI.MessageEditor` (LiveComponent)

**Streaming flow:** `Omni.Agent` GenServer → sends `{:agent, pid, type, data}` process messages → LiveView `handle_info` → builds up `@current_turn` from deltas → on `:done`, pushes completed turn onto `@streams.turns` via `Turn.from_omni/2` → function components re-render.

**Turn-based rendering:** The LiveView maintains a stream of `OmniUI.Turn` structs optimised for rendering, separate from the agent's internal message tree. Each agent prompt round collapses into one turn — a user message paired with an accumulated assistant response. See `context/vision.md` "Phase 1 Learnings" and `context/architecture.md` for details.

**Attachments:** `MessageEditor` uses LiveView's built-in upload system (`allow_upload/3`, `live_file_input`, `phx-drop-target`) for click-to-attach and drag-and-drop. On submit, files are base64-encoded into `Omni.Content.Attachment` structs. A shared `attachment/1` component renders attachment tiles in both the editor (with cancel action) and the message list (read-only).

**CSS theming:** `priv/static/omni_ui.css` defines a semantic color token system (`omni-bg`, `omni-text-1..4`, `omni-border-1..3`, `omni-accent-1..2`) using Tailwind 4's `@theme` directive with OKLCH values and a dark mode variant. Components use these tokens exclusively — no hardcoded colors except for semantic accents (green for success, red for errors, amber for thinking). Consumers can override the theme by redefining the CSS custom properties.

## Key Dependencies

- **`omni`** — Unified LLM client (Anthropic, OpenAI, Google, etc.)
- **`phoenix_live_view`** — Real-time UI components
- **Tailwind CSS 4** — Styling via semantic color tokens defined in `priv/static/omni_ui.css`
