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

- Persistence (conversations, settings)
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

### 2. Persistence

**Status:** Design needed, follows macro extraction.

The Tree structure changes the persistence question. It's not about serializing a flat message list — it's about saving and restoring `OmniUI.Tree` with all branches, cursors, and usage data.

**Key design questions:**

- **What gets persisted?** The tree (conversation history with branches), settings (model, thinking mode), and potentially artifacts. These may be separate concerns with separate storage.
- **Behaviour API:** A `Store` behaviour with `save_conversation/2`, `load_conversation/1`, `list_conversations/0` as the starting point. What are the argument/return types? Does the store receive the raw tree or a serialization-friendly representation?
- **Who triggers persistence?** The macro (auto-save after each turn)? The developer (explicit save calls)? Configurable? Auto-save is convenient but may not suit all use cases.
- **Session management:** Multiple conversations, switching between them, creating new ones. This is UI work (conversation list, new chat button) plus state management (swapping trees, resetting agent context).
- **Default adapter:** Ship a filesystem adapter for development. ETS or database adapters left to the community or documented as examples.

**Hooks:** The `agent_event/3` callback provides the natural persistence hook — the developer can save after each completed turn via `agent_event(:done, response, socket)`.

### 3. Advanced Tooling

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

### 4. Polish & Release

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
2. **Conversation persistence** — tree serialization, Store behaviour, session management, settings. Builds on the macro's state model while the problem is relatively bounded. Gets the infrastructure in place before the complexity of tooling.
3. **Advanced tooling** — artifacts, code sandbox. With persistence already in place, artifact storage becomes an extension of an existing pattern. Design can focus on the interesting interaction and rendering problems rather than fighting infrastructure.
4. **Polish** items can be picked up incrementally at any point.

Artifact *storage* specifically is hard to design before knowing what an artifact is — that part of persistence will naturally emerge from the tooling work and extend the Store behaviour established in step 2.

---

## Open Questions

- **Persistence shape** — how does save/load interact with the tree-based data model? Serializing `OmniUI.Tree` directly vs a normalized format? How do branches serialize?
- **Agent API gaps** — does `Omni.Agent` need new callbacks for persistence hooks, lifecycle events, or state snapshots? This is a key output of building the macro.
- **Artifact identity** — if artifacts are versioned and editable, they need their own data model. How does this relate to the conversation tree? Is an artifact a node in the tree, a side structure, or something else entirely?
