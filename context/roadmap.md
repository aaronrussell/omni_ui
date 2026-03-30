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

### 3. Persistence Follow-ups

**Status:** Future enhancements documented in `persistence.md` § "Future Work".

- **Incremental saves** — buffer new node IDs and pass as `:new_node_ids` to `save_tree`, so adapters can append rather than full-overwrite. The API already accepts the opt; adapters ignore it for now.
- **JSON serialization** — human-readable storage format replacing opaque ETF. Requires `Omni.Message`/`Omni.Content.*` serialization in the `omni` package.
- **Session browser component** — UI for listing and switching sessions. Needs to work both router-mounted (push_patch) and embedded (events). `update_agent(tree: ...)` already handles the session switch.
- **Save on metadata-only changes** — model/thinking/navigation changes aren't persisted yet. Options: developer overrides `handle_event`, new `ui_event/3` callback, or AgentLive handles directly.
- **Error handling in saves** — current implementation is fire-and-forget. Logging, retry, flash notifications are the developer's concern via `agent_event/3`.

### 4. Advanced Tooling

**Status:** Requires design exercise before implementation.

Two interrelated pieces: an artifacts system for rendering rich tool output, and a code sandbox for executing agent-generated code.

#### Artifacts

**What is an artifact?** The working definition: a piece of content produced by a tool call that deserves its own rendering context — not just inline text in the conversation. Examples: generated HTML pages, interactive visualizations, diagrams, structured data views.

**Key design questions:**

- **Rendering model:** How does an artifact get rendered? Options range from simple (iframe with HTML string) to complex (dynamically compiled LiveView components). The iframe approach is safer and simpler but limits interactivity. LiveView components are powerful but raise trust/sandboxing questions.
- **UI surface:** Side panel (like Claude's artifacts)? Inline expansion? Full-screen takeover? Multiple artifacts visible simultaneously? The `AgentLive` template already has a placeholder for an artifacts panel.
- **Artifact lifecycle:** Are artifacts ephemeral (live only during the session) or persistent? Can the user edit an artifact? Can the agent iterate on a previous artifact? If so, artifacts need identity and versioning — possibly another tree structure.
- **Tool integration:** How does a tool declare that its output is an artifact vs inline content? Is this a convention in the tool result's content, a separate field, or a tool registration option?

#### Code Sandbox

**Key design questions:**

- **What executes?** Elixir code via the BEAM? JavaScript in a browser sandbox? Both? Elixir execution is natural for the ecosystem but raises safety questions. JS execution is well-understood (iframe sandbox) but less interesting for an Elixir-native toolkit.
- **Elixir sandboxing:** If we execute Elixir, how do we isolate it? Options: separate node, restricted module access via `Code.eval_string` wrapper, Docker container. Each has different tradeoffs in safety, latency, and capability.
- **Interaction with artifacts:** Code execution output often *is* the artifact (a generated chart, a computed dataset, a rendered HTML page). The sandbox and artifact systems need to be designed together.
- **Tool definition:** Is the sandbox itself a tool the agent calls? Or is it infrastructure that tools can invoke? The agent probably needs a `run_code` tool that produces artifact output.

**Approach:** Start with the simplest useful thing — an HTML artifact renderer (iframe) triggered by a tool result. This proves the artifact UI, tool integration, and panel layout without solving sandboxing. Code execution is a separate step that builds on the artifact surface.

### 5. Polish & Release

Smaller items that don't require major design work but need to happen before a public release.

- **Error retry** — errored turns preserve the user message. Add a retry button that re-prompts the agent. Straightforward given the current tree/turn architecture.
- **Streaming performance** — debounce text deltas (50-100ms timer) to reduce re-renders during fast streaming. Called out as a TODO in the code.
- **Package API surface** — decide what's public vs internal. `OmniUI.Components`, `OmniUI.Turn`, `OmniUI.Tree` are public. Helpers, TreeFaker, internal structs may not be.
- **Documentation** — hex docs, usage guides, example configurations. Deferred until API stabilises post-macro extraction.
- **Testing** — expand test coverage as the public API solidifies. Current tests cover data structures and components; integration tests for the full streaming lifecycle would be valuable.

---

## Sequencing

The workstreams are sequential where it matters:

1. ~~**Macro**~~ — done.
2. ~~**Persistence**~~ — done. Store behaviour, filesystem adapter, macro integration, AgentLive session management.
3. **Persistence follow-ups** — incremental saves, JSON format, session browser, metadata-only saves. Can be picked up as needed.
4. **Advanced tooling** — artifacts, code sandbox. With persistence in place, artifact storage extends the existing Store pattern.
5. **Polish** items can be picked up incrementally at any point.

Artifact *storage* specifically is hard to design before knowing what an artifact is — that part will naturally emerge from the tooling work and extend the Store behaviour.

---

## Open Questions

- **Artifact identity** — if artifacts are versioned and editable, they need their own data model. How does this relate to the conversation tree? Is an artifact a node in the tree, a side structure, or something else entirely?
