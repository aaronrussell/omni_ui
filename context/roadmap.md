# OmniUI Roadmap

A LiveView component kit for building agent chat interfaces, powered by Omni. Lightweight, hackable, and composable — designed to demo Omni and give developers building blocks for their own agent UIs.

---

## Architecture Vision

Three layers — developers pick their entry point based on how much control they want.

1. **Function Components** (Layer 1) — pure rendering, zero state. The hackable building blocks. All live in `OmniUI.Components`. Developers can use any component individually, restyle them, skip ones they don't need, or replace them with their own.
2. **`use OmniUI` Macro** (Layer 2) — adds agent capabilities to any LiveView. Injects streaming plumbing, state management, and init so the developer owns their template entirely while OmniUI handles the wiring.
3. **`OmniUI.AgentLive`** (Layer 3) — mountable LiveView. The "just give me an agent" entry point. A reference implementation built with Layers 1 and 2.

All three layers are built. Layer 2 was extracted from the working Layer 3 code — `AgentLive` is now the first consumer of the macro.

See `architecture.md` for the current component hierarchy, data structures, and streaming flow.

---

## Current State

**What's built:**

- Chat interface with streaming responses, markdown rendering, thinking blocks, tool use with paired results
- `OmniUI.Tree` — branching conversation history with cursor-based navigation
- `OmniUI.Turn` — rendering-optimized views computed from the tree
- `TurnComponent` — inline editing, copy-to-clipboard, branch navigation (edits + regenerations)
- `EditorComponent` — text input with drag-and-drop file attachments
- Toolbar with model selection and thinking mode toggle
- Semantic CSS theming via OKLCH color tokens with dark mode

**What's not built:**

- Persistence follow-ups (incremental saves, JSON format, session browser, metadata-only saves)
- Artifacts panel and advanced tooling
- Error retry mechanism
- Package polish (public API surface, docs, hex publishing)

---

## Workstreams

### 1. `use OmniUI` Macro (done)

Extracted the streaming plumbing from `AgentLive` into a macro. A developer writes `use OmniUI`, implements `render/1` and `mount/3` (calling `start_agent/2`), and gets full agent chat capabilities.

**What was built:**

- `OmniUI` behaviour with `agent_event/3` callback — fires for every agent event after default handling, letting developers observe/react to streaming events, completions, and errors
- `__using__/1` macro — registers `@before_compile`, imports components and `start_agent/2`/`update_agent/2`
- `__before_compile__/1` — injects `handle_event/3` and `handle_info/2` clauses with `defoverridable` wrapping so developer handlers coexist transparently
- `OmniUI.Handlers` — all event/message handling as pure functions, with `handle_agent_event/3` as single dispatch point for all agent streaming events
- `start_agent/2` — initialises agent process, tree, stream, and assigns in mount
- `update_agent/2` — partial updates to model, thinking, system, tools with agent sync
- `AgentLive` refactored to ~70 lines: just `use OmniUI`, render, and mount

### 2. Persistence (done)

Pluggable session persistence with URL-based session management. See `persistence.md` for the full design spec.

**What was built:**

- `OmniUI.Store` behaviour — five callbacks (`save_tree`, `save_metadata`, `load`, `list`, `delete`) with scoping via opts and adapter-managed timestamps
- `OmniUI.Store.Filesystem` — ETF-based development adapter, two files per session (`tree.etf`, `meta.etf`), scoped and unscoped paths
- `Tree.new/1` — reconstructs a tree from saved parts (nodes, path, cursors), for future non-ETF adapters
- Macro injects store functions (`save_tree`, `save_metadata`, `load_session`, `list_sessions`, `delete_session`) resolved from `use OmniUI, store: Module` or app config; no-ops when unconfigured
- `update_agent/2` extended with `:tree` option — resets agent context, rebuilds turns stream, syncs assigns
- `AgentLive` uses `handle_params/3` for session routing (`/?session_id=abc`), persists tree + metadata in `agent_event(:done)`

### 3. Advanced Tooling (done)

Artifacts system and code sandbox. See `architecture.md` for the design.

**What was built:**

- **Artifacts** — session-scoped files the agent creates via a single tool (write, patch, get, list, delete). Disk-based storage co-located with session data. HTTP serving via `Artifacts.Plug` with signed tokens. Self-contained `PanelComponent` with rendering modes (iframe preview, syntax-highlighted source, markdown, media, download). Custom inline chat components for both tools.
- **Code Sandbox** — per-execution Elixir sandbox via `:peer` nodes. IO capture via host-local StringIO. Environment-aware tool descriptions. Extension mechanism connecting sandbox to artifacts (`Artifacts.REPLExtension` injects an `Artifacts` facade module into the peer).
- **Custom tool-use components** — `content_block/1` dispatcher supports per-tool custom components via `@tool_components` map. `Artifacts.ChatUI` wraps the default renderer with an `:aside` slot; `REPL.ChatUI` replaces it entirely.

### 4. Persistence Follow-ups

**Status:** Future enhancements documented in `persistence.md` § "Future Work".

- **Incremental saves** — buffer new node IDs and pass as `:new_node_ids` to `save_tree`, so adapters can append rather than full-overwrite. The API already accepts the opt; adapters ignore it for now.
- **JSON serialization** — human-readable storage format replacing opaque ETF. Requires `Omni.Message`/`Omni.Content.*` serialization in the `omni` package.
- **Session browser component** — UI for listing and switching sessions. Needs to work both router-mounted (push_patch) and embedded (events). `update_agent(tree: ...)` already handles the session switch.
- **Save on metadata-only changes** — model/thinking/navigation changes aren't persisted yet. Options: developer overrides `handle_event`, new `ui_event/3` callback, or AgentLive handles directly.
- **Error handling in saves** — current implementation is fire-and-forget. Logging, retry, flash notifications are the developer's concern via `agent_event/3`.

### 5. Polish & Release

Smaller items that don't require major design work but need to happen before a public release.

- **Error retry** — errored turns preserve the user message. Add a retry button that re-prompts the agent. Straightforward given the current tree/turn architecture.
- **Streaming tool-use headers** — tool_use blocks currently only render once the tool_use content has fully streamed. Should render the header (icon, tool name/title) as soon as the first chunk arrives so the user gets visual feedback that something is happening.
- **Streaming performance** — debounce text deltas (50-100ms timer) to reduce re-renders during fast streaming. Called out as a TODO in the code.
- **Per-tool timeouts** — the agent currently has a single timeout applied to all tool calls, and the REPL tool has its own separate timeout setting. Needs exploration: can tools declare their own timeout that overrides the agent default? Likely requires changes in `omni`.
- **REPL tool packaging** — the REPL tool (`OmniUI.REPL.Sandbox`, `REPL.Tool`, `REPL.SandboxExtension`) has no UI dependency — it could live in `omni` or a separate package alongside `Omni.Agent`. Artifacts is different (needs the panel UI). Needs a conversation about where the boundary is.
- **Project namespacing** — `OmniUI` vs `Omni.UI`. The rest of the ecosystem uses the `Omni` namespace (`Omni.Agent`, etc.). Needs a decision on whether to align (and what the migration looks like).
- **Package API surface** — decide what's public vs internal. `OmniUI.Components`, `OmniUI.Turn`, `OmniUI.Tree` are public. Helpers, TreeFaker, internal structs may not be.
- **Documentation** — hex docs, usage guides, example configurations. Including artifact/sandbox setup (ArtifactPlug router requirements, tool registration).
- **Cross-browser QA** — thorough testing across browsers. The artifacts panel specifically won't work well on mobile — need to figure out the responsive approach (full-screen takeover? separate route? hidden on mobile?).
- **Testing** — expand test coverage as the public API solidifies. Current tests cover data structures and components; integration tests for the full streaming lifecycle would be valuable.

---

## Sequencing

The workstreams are sequential where it matters:

1. ~~**Macro**~~ — done.
2. ~~**Persistence**~~ — done. Store behaviour, filesystem adapter, macro integration, AgentLive session management.
3. ~~**Advanced tooling**~~ — done. Artifacts, code sandbox, custom tool-use components. See `architecture.md`.
4. **Persistence follow-ups** — incremental saves, JSON format, session browser, metadata-only saves. Can be picked up as needed.
5. **Polish** items can be picked up incrementally at any point.
