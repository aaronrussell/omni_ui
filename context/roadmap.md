# OmniUI Roadmap

A LiveView component kit for building agent chat interfaces, powered by Omni. Lightweight, hackable, and composable — designed to demo Omni and give developers building blocks for their own agent UIs.

---

## Architecture Vision

Three layers — developers pick their entry point based on how much control they want.

1. **Function Components** (Layer 1) — pure rendering, zero state. The hackable building blocks. All live in `OmniUI.Components`. Developers can use any component individually, restyle them, skip ones they don't need, or replace them with their own.
2. **`use OmniUI` Macro** (Layer 2) — adds agent capabilities to any LiveView. Injects streaming plumbing, state management, and init so the developer owns their template entirely while OmniUI handles the wiring.
3. **`OmniUI.AgentLive`** (Layer 3) — mountable LiveView. The "just give me an agent" entry point. A reference implementation built with Layers 1 and 2.

Layer 1 is complete. Layer 3 exists as a hand-wired implementation. Layer 2 is the next major piece — extracting the macro from the working code.

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

- `use OmniUI` macro (Layer 2)
- Persistence (conversations, settings)
- Artifacts panel and advanced tooling
- Error retry mechanism
- Package polish (public API surface, docs, hex publishing)

---

## Workstreams

### 1. `use OmniUI` Macro

**Status:** Requires design exercise before implementation.

Extract the streaming plumbing from `AgentLive` into a macro that any LiveView can `use`. The goal: a developer writes `use OmniUI` and gets agent chat capabilities without reimplementing the event handling, state management, or tree operations.

**Key design questions:**

- **What state does the macro manage?** Currently `AgentLive` holds: `tree`, `current_turn`, `agent`, `model`, `thinking`, `usage`, plus the `:turns` stream. Which of these are the macro's responsibility vs the developer's?
- **What gets injected?** The `handle_info` clauses for agent events are the obvious candidate. But what about `handle_event` for `navigate`, `regenerate`? Those feel like they belong to the macro too — they're tree operations, not app-specific logic.
- **What's the init API?** `OmniUI.init(socket, opts)` needs to set up the tree, agent, and stream. What options does it accept? Model, provider, tools, system prompt, thinking mode, existing conversation (for restore)?
- **What callbacks does the developer get?** Hooks for: message submitted (before prompt), turn completed (after stream insert), error occurred? Or is `handle_info` passthrough sufficient?
- **How does the developer extend behaviour?** If the developer also needs `handle_info` for their own messages, how do macro-injected clauses and developer clauses coexist? `__before_compile__` vs `defoverridable` vs explicit delegation?
- **Where do tree mutations live?** Editing and regeneration involve tree navigation, agent context sync, and stream resets. These are complex multi-step operations. Should they be macro-injected `handle_info`/`handle_event` clauses, or public API functions the developer calls?
- **Template ownership:** The developer owns their template entirely. The macro provides assigns, the developer renders them. But should the macro provide any helper functions for common template patterns?

**Approach:** Extract from working code. `AgentLive` becomes the first consumer of the macro — refactored to `use OmniUI` as proof that the extraction works. If `AgentLive` can be cleanly rebuilt on the macro, the API is right.

### 2. Persistence

**Status:** Design needed, follows macro extraction.

The Tree structure changes the persistence question. It's not about serializing a flat message list — it's about saving and restoring `OmniUI.Tree` with all branches, cursors, and usage data.

**Key design questions:**

- **What gets persisted?** The tree (conversation history with branches), settings (model, thinking mode), and potentially artifacts. These may be separate concerns with separate storage.
- **Behaviour API:** A `Store` behaviour with `save_conversation/2`, `load_conversation/1`, `list_conversations/0` as the starting point. What are the argument/return types? Does the store receive the raw tree or a serialization-friendly representation?
- **Who triggers persistence?** The macro (auto-save after each turn)? The developer (explicit save calls)? Configurable? Auto-save is convenient but may not suit all use cases.
- **Session management:** Multiple conversations, switching between them, creating new ones. This is UI work (conversation list, new chat button) plus state management (swapping trees, resetting agent context).
- **Default adapter:** Ship a filesystem adapter for development. ETS or database adapters left to the community or documented as examples.

**Dependency:** The macro design (Workstream 1) affects where persistence hooks live. Design persistence after the macro API stabilises but before advanced tooling — so the Store behaviour is in place when artifacts need storage.

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

1. **Macro** — critical path. Defines the developer-facing API and state model that everything else builds on.
2. **Conversation persistence** — tree serialization, Store behaviour, session management, settings. Builds on the macro's state model while the problem is relatively bounded. Gets the infrastructure in place before the complexity of tooling.
3. **Advanced tooling** — artifacts, code sandbox. With persistence already in place, artifact storage becomes an extension of an existing pattern. Design can focus on the interesting interaction and rendering problems rather than fighting infrastructure.
4. **Polish** items can be picked up incrementally at any point.

Artifact *storage* specifically is hard to design before knowing what an artifact is — that part of persistence will naturally emerge from the tooling work and extend the Store behaviour established in step 2.

---

## Open Questions

- **Persistence shape** — how does save/load interact with the tree-based data model? Serializing `OmniUI.Tree` directly vs a normalized format? How do branches serialize?
- **Agent API gaps** — does `Omni.Agent` need new callbacks for persistence hooks, lifecycle events, or state snapshots? This is a key output of building the macro.
- **Artifact identity** — if artifacts are versioned and editable, they need their own data model. How does this relate to the conversation tree? Is an artifact a node in the tree, a side structure, or something else entirely?
