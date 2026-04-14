# Architecture Decisions

Architectural decisions and current design. Covers the data model, component hierarchy, streaming flow, and the `use OmniUI` macro.

---

## Source of Truth

The LiveView owns conversation state. `OmniUI.Tree` is the authoritative store — a branching tree of messages held in the socket's assigns. The `Omni.Agent` GenServer is a downstream consumer: before each prompt the macro's handlers sync the agent's context to match the tree via `Omni.Agent.set_state/3`. This ensures that after edits, regenerations, or branch switches the agent always works with the correct message history.

Turns are computed views over the tree, never stored. `Turn.all/1` reduces the active path into a list of renderable turns on demand — after navigation, edits, or initial mount.

---

## Data Structure: Tree

`OmniUI.Tree` stores the full conversation history as a tree of nodes:

```elixir
%OmniUI.Tree{
  nodes: %{node_id() => tree_node()},   # All nodes
  path: [node_id()],                    # Active path from root to head
  cursors: %{node_id() => node_id()}    # Tracks which child is "active" at each branch point
}

# Each node:
%{
  id: node_id(),
  parent_id: node_id() | nil,
  message: Omni.Message.t(),
  usage: Omni.Usage.t() | nil           # Populated on the last message of a completed turn
}
```

**Why a tree:**

- **Edits** create sibling user messages under the same parent.
- **Regenerations** create sibling assistant messages under the same user message.
- **Branch switching** navigates to a different path through the tree without losing any history.
- The active path is a flat walk through the tree — `messages/1` extracts it as a message list for syncing to the agent.

**Key operations:**

| Function | Purpose |
|----------|---------|
| `push/3`, `push_node/3` | Append a message to the head of the active path |
| `navigate/2` | Set a new active path by walking parent pointers from a node to root |
| `extend/1` | Walk from current head to a leaf following cursors (used after `navigate` to a mid-tree node) |
| `children/2` | Get all child node IDs of a given node |
| `messages/1` | Flatten active path to a list of `Omni.Message` structs |
| `usage/1` | Cumulative usage across all nodes in the tree |

**Cursors** remember which child was last selected at each branch point. After `navigate/2` moves the path to a mid-tree node, `extend/1` follows cursors to walk back to a leaf — the user stays on the branch they expect.

`Tree` implements `Enumerable`, yielding tree nodes along the active path in root-to-leaf order.

---

## Data Structure: Turns

Each turn collapses a sequence of tree nodes — one user prompt, any intermediate tool-use rounds, and the accumulated assistant response — into a single renderable struct. Turns are the UI's unit of display: one user question paired with one complete agent response.

```elixir
%OmniUI.Turn{
  id: node_id(),                           # Node ID of the user message
  res_id: node_id() | nil,                 # Node ID of the first assistant message (nil while streaming)
  status: :complete | :streaming | :error,

  # User message (pre-separated)
  user_text: [Omni.Content.Text.t()],
  user_attachments: [Omni.Content.Attachment.t()],
  user_timestamp: DateTime.t() | nil,

  # Assistant response (all content blocks merged across all assistant messages)
  content: [Omni.Message.content()],       # Text, Thinking, ToolUse
  timestamp: DateTime.t() | nil,           # From last assistant message, nil while streaming
  tool_results: %{tool_use_id => ToolResult},

  # Metadata
  error: String.t() | nil,
  usage: Omni.Usage.t(),

  # Branching metadata
  edits: [node_id()],                      # All sibling user messages (including active), sorted
  regens: [node_id()]                      # All sibling assistant messages (including active), sorted
}
```

- **`edits`** — sibling user messages sharing the same parent. Length > 1 means the user edited their prompt. The active node (`id`) is included so components can compute position (e.g. "2/3").
- **`regens`** — sibling assistant messages that are children of this turn's user message. Length > 1 means the user regenerated the response.

`Turn.all/1` chunks the tree's active path at turn boundaries (user messages that aren't tool results), building a turn from each chunk with `edits` and `regens` populated from the full tree. `Turn.get/2` returns a single turn by node ID. `Turn.new/3` builds a turn from raw messages (used when completing a streaming turn).

Helper functions `push_content/2`, `push_delta/2`, and `put_tool_result/2` handle streaming accumulation on `@current_turn`. Components never touch `Omni.Turn` or `OmniUI.Tree` directly.

---

## `use OmniUI` Macro

The macro adds agent chat capabilities to any LiveView. The developer writes `use OmniUI`, implements `render/1` and `mount/3`, and gets full streaming, tree operations, and event handling injected automatically.

**What the macro injects:**

- `handle_event/3` clauses for `"omni:*"` events (navigate, regenerate, select_model, select_thinking, plus message events from live components)
- `handle_info/2` clauses for `{OmniUI, ...}` component messages and `{:agent, ...}` streaming events
- Default `agent_event/3` and `ui_event/3` callbacks (pass-through) if the developer doesn't define them
- Imports: `OmniUI.Components`, `start_agent/2`, `update_agent/2`

**Coexistence with developer handlers:** Uses `@before_compile` with `defoverridable` — OmniUI events are dispatched first, unrecognised events fall through to the developer's clauses via `super`. The wrapping is transparent.

**`agent_event/3` callback:** Fires for every agent streaming event after OmniUI's default handling. Receives the event atom, event data, and already-updated socket. The developer can observe any event — streaming deltas, completions, errors — and mutate the socket further.

**`ui_event/3` callback:** Fires for UI events that OmniUI itself handles, after the macro has processed them. Receives the event atom, event data, and updated socket. Use it to observe or react to user actions that mutate agent-related state — for example, persisting model/thinking changes.

Events that fire:

| Event | Data | Represents |
|-------|------|------------|
| `:model_changed` | `%Omni.Model{}` | toolbar selection |
| `:thinking_changed` | `false \| :low \| :medium \| :high \| :max` | toolbar toggle |
| `:navigated` | `node_id` | tree cursor moved to a branch |
| `:message_sent` | `{node_id, %Omni.Message{}}` | user sent a message |
| `:message_edited` | `{node_id, %Omni.Message{}}` | user edited a prior message (new branch) |

**Event ownership.** The rule: *the macro handles events that mutate agent state or agent context; everything else is the consumer's.* Consumer-owned events (title editing, session management, artifacts, custom UI) go through standard `handle_event/3` — they never reach `ui_event/3`. This keeps the boundary clean: `ui_event/3` is for observing macro-handled state changes, nothing else.

**Key modules:**

- `OmniUI` — macro, behaviour, `start_agent/2`, `update_agent/2`
- `OmniUI.Handlers` — pure functions for all event/message handling. `handle_event/3` for UI events, `handle_info/2` for component messages, `handle_agent_event/3` for all agent streaming events.
- `OmniUI.AgentLive` — reference implementation built with the macro. Just render + mount (~70 lines).

## Naming: AgentLive + chat_interface

- **`OmniUI.AgentLive`** — the mountable LiveView. The batteries-included "just give me an agent" entry point. Built with `use OmniUI`.
- **`chat_interface/1`** — function component composing the message stream, streaming turn, and editor. The reusable chat UI that doesn't care what drives it.

"Agent" is the product (tools, artifacts, the works). "Chat" is the UI pattern (messages, editor, streaming). A developer who wants the full package mounts `AgentLive`. A developer who wants just chat in their own LiveView writes `use OmniUI` and composes the components in their own template.

---

## Component Structure

```
AgentLive (LiveView)
├── chat_interface/1 (function component — root wrapper)
│   ├── message_list/1 (function component — scroll container)
│   │   └── Stream of TurnComponent (LiveComponent — one per completed turn)
│   │       ├── turn/1 (function component — pairs user + assistant slots)
│   │       │   ├── user_message/1 or inline edit form (when editing)
│   │       │   │   ├── text content blocks
│   │       │   │   └── attachment/1 tiles (read-only)
│   │       │   └── assistant_message/1
│   │       │       └── content_block/1 (pattern-matched: Text, Thinking, ToolUse, Attachment)
│   │       │                          — ToolUse dispatches via @tool_components (see below)
│   │       ├── user_message_actions/1 (copy, edit, version nav)
│   │       └── assistant_message_actions/1 (copy, redo, version nav, usage)
│   │
│   ├── turn/1 for @current_turn (function component — visible while streaming)
│   │   ├── user_message/1
│   │   └── assistant_message/1 (streaming indicators)
│   │
│   ├── EditorComponent (LiveComponent)
│   │   ├── textarea + submit button
│   │   ├── drag-drop zone (phx-drop-target)
│   │   ├── attachment previews (using shared attachment/1 component)
│   │   │   └── cancel button per entry (via :action slot)
│   │   ├── attach button (label wrapping hidden live_file_input)
│   │   └── :toolbar slot
│   │
│   ├── toolbar/1 (function component — model selector, thinking toggle, usage)
│   └── footer slot
│
├── header/1 (private function component — top bar)
│   ├── Sessions drawer toggle + New session button
│   ├── Title input (inline-editable via phx-blur / phx-submit)
│   └── Artifacts panel toggle button
│
├── Artifacts.PanelComponent (LiveComponent — toggled via @view_artifacts)
│
└── SessionsComponent (LiveComponent — drawer, toggled via @view_sessions)
    └── session_list/1 (function component — rows + :actions slot)
```

**Two LiveComponents:**

- **`TurnComponent`** — renders a completed turn from the `:turns` stream. Owns inline editing state (textarea input, edit mode toggle) and handles copy-to-clipboard. Forwards `"omni:navigate"` and `"omni:regenerate"` events to the parent via `phx-click`; sends `{OmniUI, :edit_message, turn_id, message}` to the parent on edit submit.
- **`EditorComponent`** — owns composition state (textarea input, file uploads via `allow_upload/3`). Supports click-to-attach and drag-and-drop. On submit, base64-encodes files into `Omni.Content.Attachment` structs, builds an `Omni.Message`, and sends `{OmniUI, :new_message, message}` to the parent. High-frequency keystroke and upload state stays isolated from the parent.

**The streaming turn is a function component**, not a LiveComponent. The LiveView keeps `@current_turn` in its assigns and renders it with the same `turn/1` component used inside `TurnComponent`. LiveView's change tracking means only the template block referencing `@current_turn` re-evaluates on each delta — the stream of completed turns is untouched. The DOM diff sent over the wire is small (just appended text).

If streaming performance becomes an issue, two non-architectural fixes are available: debouncing deltas (batch on a 50-100ms timer), or deferring markdown rendering to the client via a JS hook.

---

## Custom Tool-Use Components

Tool-use content blocks can be rendered with per-tool custom components. The `ToolUse` clause of `content_block/1` is a dispatcher: it looks up the tool's name in a `@tool_components` map (`%{tool_name => (assigns -> rendered)}`); if found, it calls that function, otherwise falls back to a built-in `default_tool_use/1` renderer.

**Registration.** The map is built at tool registration time. `start_agent/2` and `update_agent/2` accept a `:tools` list of mixed shapes:

```elixir
%Omni.Tool{}                              # default rendering
{%Omni.Tool{}, component: fun}            # custom rendering
```

A private `normalise_tools/1` in `OmniUI` splits the list into a flat `[%Omni.Tool{}]` (handed to `Omni.Agent`) and a `%{name => component_fun}` map (assigned to `:tool_components` on the socket). The tuple's keyword list is forward-compatible — sibling keys like `:title`, `:icon`, `:result_block` can be added later without breaking existing call sites.

**Propagation.** `@tool_components` is threaded through the component tree: `AgentLive → TurnComponent → assistant_message/1 → content_block/1`. `TurnComponent` defaults it to `%{}` in `mount/1` so tests and callers without custom components work unchanged.

**Assigns contract.** Custom components (and `default_tool_use/1`) receive a normalised assigns map — *not* the raw `content_block` assigns:

- `@tool_use` — the `%Omni.Content.ToolUse{}` struct
- `@tool_result` — the matching `%Omni.Content.ToolResult{}` or `nil` (pre-resolved from `:tool_results` so custom components don't re-do the lookup)
- `@streaming` — boolean

Dispatcher state (`@tool_components`, the full `@tool_results` map) is deliberately *not* leaked into custom components.

**Event handling.** Custom components can include interactive elements (e.g. a "View artifact" button) using standard `phx-click`. Events without a `phx-target` bubble up through the `TurnComponent` to the parent LiveView, where the developer handles them in their own `handle_event/3`. No framework-level event plumbing.

**Sharp edge.** `@tool_components` is captured at `stream_insert` time for each `TurnComponent`. If the developer hot-swaps tools mid-session (via `update_agent`), already-rendered stream items don't pick up the new map. In practice `:tools` is set in `handle_params/3` alongside the tree, before turns are populated, so this doesn't bite. If mid-session swaps become a use case, reset the `:turns` stream afterwards.

---

## Streaming Architecture

1. **User submits** → `EditorComponent` sends `{OmniUI, :new_message, message}` → macro's injected `handle_info` delegates to `OmniUI.Handlers` → pushes message to tree, prompts agent, sets `@current_turn` (with `status: :streaming`)
2. **Agent streaming events** → injected `handle_info` calls `Handlers.handle_agent_event/3` → updates `@current_turn` via `Turn.push_content/2`, `push_delta/2`, `put_tool_result/2` → calls `agent_event/3` on the consuming module
3. **Agent `:done`** → pushes all response messages to tree → computes `edits`/`regens` from tree children → builds completed turn via `Turn.new/3` → `stream_insert(:turns, turn)` → clears `@current_turn` → calls `agent_event(:done, response, socket)`
4. **Agent `:error`** → `stream_insert` the current turn with `status: :error` → clears `@current_turn` → calls `agent_event(:error, reason, socket)`

Streaming state is determined by `@current_turn != nil` — no separate boolean flag.

LiveView's change tracking ensures only the `@current_turn` portion of the template re-evaluates on each delta. The stream of completed turns is not re-rendered.

---

## Editing and Regeneration

Both operations create new branches in the tree.

**Editing a user message:**

1. `TurnComponent` sends `{OmniUI, :edit_message, turn_id, message}` to parent
2. Macro's injected handler navigates tree to the **parent** of the edited message (so `push_node` creates a sibling)
3. Pushes new user message → new branch from the same parent
4. Syncs agent context to tree messages *before* the new user message
5. Prompts agent with new content, resets `:turns` stream

**Regenerating a response:**

1. Macro's injected handler receives `"omni:regenerate"` event with `turn_id`
2. Navigates tree so head = the user message node (new response branches from here)
3. Syncs agent context to tree messages *before* the user message
4. Prompts agent with original user content, resets `:turns` stream

Both flows end with the same streaming lifecycle: `@current_turn` accumulates deltas, `:done` pushes the completed turn to the stream.

**Branch switching** uses `Tree.navigate/2` + `Tree.extend/1` to set the new active path, then recomputes all turns via `Turn.all/1` and resets the stream with `stream(:turns, turns, reset: true)`.

---

## Persistence

Session persistence is provided by `OmniUI.Store` as a standalone subsystem — it has no integration with the `use OmniUI` macro, and the macro has no knowledge of it. The macro is focused on agent-streaming plumbing and UI event handling; persistence is something consumers call into directly.

**Public API.** `OmniUI.Store` is both a behaviour (for adapters) and a public module (for consumers). Consumers call it directly:

```elixir
OmniUI.Store.save_tree(session_id, tree, opts)
OmniUI.Store.save_metadata(session_id, metadata, opts)
OmniUI.Store.load(session_id, opts)
OmniUI.Store.list(opts)
OmniUI.Store.delete(session_id, opts)
```

Each function reads the configured adapter at runtime. When no adapter is configured, the functions are no-ops (return `:ok` or `{:ok, []}` as appropriate). Scoping, limits, and offsets pass through `opts`.

**Adapter configuration.**

```elixir
config :omni_ui, store: OmniUI.Store.FileSystem
```

`:store` in opts overrides the configured adapter for a specific call.

**Why standalone rather than macro-injected?** Persistence policy — *when* to save, *what* scope to use, error handling, retry behaviour — varies between consumers. The macro provides plumbing every consumer needs; persistence is a separate concern each consumer wires up to fit their model. AgentLive is one example: it calls `save_tree` on `agent_event(:stop, ...)`, calls `save_metadata` from `ui_event/3` to persist model/thinking changes, and calls `save_metadata` directly from the title blur handler.

**Adapters.** `OmniUI.Store.FileSystem` is the shipped adapter — JSON/JSONL files per session directory (see the adapter's moduledoc for the file format). Consumers implement the `OmniUI.Store` behaviour for Ecto, Redis, or other backends.

---

## Sessions

Sessions are identified by a URL param (`?session_id=<id>`) and persisted via `OmniUI.Store`. `AgentLive.handle_params/3` has three clauses:

1. **Re-entry guard** — matches when the URL's `session_id` equals the current assign; no-op. Prevents our own `push_patch` from triggering another load cycle.
2. **Load existing** — session id present. Calls `OmniUI.Store.load/1`, assigns title + tree + model + thinking, and wires up session-scoped tools via `create_tools/1`.
3. **No session id** — fresh mount or navigation to `/`. Routes through `start_new_session/2` with `replace: true`.

A private `start_new_session/2` helper is the single path for resetting to a fresh session. It's called from:

- The **New session** header button
- `handle_params` when the URL has no session id
- `handle_info({OmniUI, :active_session_deleted}, ...)` when the drawer deletes the active session

It cancels any in-flight agent response, generates a fresh id, clears the title, resets the tree via `update_agent(tree: %OmniUI.Tree{}, tools: create_tools(id))`, and `push_patch`es the URL. Consolidating here prevents the partial-reset bugs where different code paths each set up a clean session slightly differently.

### Session-scoped TurnComponent ids

Tree node ids are per-tree integer counters, so sessions produce the same stream dom_ids (`turns-5`, `turns-6`, …). If the `TurnComponent`'s id matched the dom_id, sessions would share component instances keyed by `(module, id)` and state would leak across switches (e.g. an artifact button keeping the previous session's filename).

The `:for` in the stream wraps each `TurnComponent` in a div that carries the stream's dom_id (satisfying the `phx-update="stream"` contract), while the LiveComponent id includes the session id:

```heex
<div :for={{dom_id, turn} <- @streams.turns} id={dom_id}>
  <.live_component
    module={OmniUI.TurnComponent}
    id={"#{@session_id}:#{turn.id}"}
    ... />
</div>
```

`stream_configure/3` can't solve this — it's called once and the session id isn't known at setup.

### Title generation

Titles are stored in metadata and surfaced in the header via an always-on `<input>` styled to look like plain text. `field-sizing: content` auto-sizes it; a wrapping form gives `phx-submit` on Enter, and the input has `phx-blur`. Both commit via the same `save_title` handler, which trims, no-ops on no-change, and — if the new value is empty and a title existed — saves `title: nil` as an explicit clear. The nil save re-enables auto-generation.

Auto-generation is a pure library function:

```elixir
OmniUI.Title.generate(strategy, messages, opts \\ [])
# strategy: :heuristic | Omni.Model.ref()
```

`:heuristic` truncates the first user message at a word boundary. The model branch synthesises `"User: …\n\nAssistant: …"` into a single prompt (with a system instruction asking for only a short title), so the LLM *summarises* the conversation rather than participating in it — cheaper, more reliable across providers, and naturally strips non-text content.

AgentLive is the reference integration. In `agent_event(:stop, ...)`, if the title is still nil and the config resolves to a strategy, generation kicks off via `start_async/3`. The `handle_async` success branch only applies the result if the title is still nil (race guard — the user may have typed one manually while generation was in flight). Errors log and silently skip; the next `:stop` naturally retries because title is still nil.

Config: `config :omni, OmniUI.AgentLive, title_generation:` with `:heuristic`, `:main` (reuse current model), or an explicit `{provider, model}`. Absent or `nil` disables.

### Sessions drawer

Mirrors the Layer 1 / Layer 2 split:

- **`OmniUI.Components.session_list/1`** — function component. One row per session, current-session highlight, `:actions` slot for per-row controls.
- **`OmniUI.SessionsComponent`** — LiveComponent wrapping the list with drawer chrome. Overlays the main content with a backdrop; ESC or click-outside closes. Fetches the first page on mount; "Load more" appends; deletes use inline two-step confirm. Deleting the active session sends `{OmniUI, :active_session_deleted}` to the parent.

The LiveComponent calls `OmniUI.Store.list/1` and `OmniUI.Store.delete/1` directly — no store module needs to be threaded through from the parent.

### Store pagination

`Store.list/1` accepts `:limit` and `:offset`; callers infer "has more" from returned list length. No total-count concept in the contract — avoids a second scan on filesystem-style adapters, and doesn't map cleanly to cursor-pagination backends.

### Lenient model resolution

`update_agent/2`'s `:model` clause is lenient on unresolvable refs: calls `Omni.get_model/2` and logs a warning on `{:error, _}` rather than raising. A session persisted with a model that's since been deregistered still loads, keeping the current model instead. `start_agent/2` stays strict — construction-time failures are developer errors.

Warnings are silent for now. Once the notifications system (roadmap § Polish & Release) lands, this is a prime candidate to surface to the user.

---

## Error Handling

When the agent errors during a turn:

1. Push the current turn to the stream with `status: :error`
2. The turn component renders the user message normally + error state where the assistant response would be
3. Flash message notifies the user

The user message is never lost because the turn is always pushed to the stream.

---

## CSS Theming

`priv/static/omni_ui.css` defines the visual theme using Tailwind 4's `@theme` directive. All colors are semantic tokens in OKLCH color space:

- `omni-bg`, `omni-bg-1`, `omni-bg-2` — background layers
- `omni-text-1..4` — text emphasis levels (1 = strongest, 4 = muted)
- `omni-border-1..3` — border emphasis levels
- `omni-accent-1`, `omni-accent-2` — interactive/accent colors

A dark mode variant is defined using `@variant dark`. Components use these tokens exclusively via Tailwind classes (e.g. `text-omni-text-3`, `bg-omni-bg-1`), with exceptions only for semantic colors (green/red/amber for success/error/thinking states).

Consumers override the theme by redefining the CSS custom properties (`--color-omni-*`). The `.omni-ui` class on the root `chat_interface` element scopes the component tree.

**Markdown typography** is defined as Tailwind descendant-selector classes (`[&_.mdex_*]`) on the `chat_interface` root, targeting the `.mdex` class that MDEx applies to rendered HTML. This keeps the `markdown/1` component's markup minimal while defining all typography styles once.

---

## Artifacts

Files created by the agent, persisted in the session. Artifacts are **session-scoped** and **not branch-aware** — navigating conversation branches does not rewind artifact state. This is a deliberate simplification; the alternative (reconstructing state by replaying tool calls along the active path) is too complex for the value.

**Data model:** `OmniUI.Artifacts.Artifact` struct — `filename`, `mime_type` (derived from extension), `size`, `updated_at`. Content lives on disk, not in assigns. Metadata is recovered by scanning the session's artifacts directory — no separate metadata persistence.

**Filesystem layout:** Artifacts are co-located with session data under `{base_path}/sessions/{session_id}/artifacts/`. Uses the same base path as `Store.FileSystem`. Session deletion (`File.rm_rf`) naturally cleans up artifacts.

**Tool:** Single Omni tool (`OmniUI.Artifacts.Tool`) with a `command` discriminator — `write`, `patch`, `get`, `list`, `delete`. Stateful: `init/1` receives `:session_id`, `call/2` delegates to `OmniUI.Artifacts.FileSystem`. `patch` is a targeted find-replace, more token-efficient than `write` for small changes.

**HTTP serving:** `OmniUI.Artifacts.Plug` serves files over HTTP. URLs use signed `Phoenix.Token` encoding the session ID — the LiveView signs, the Plug verifies. Path containment check prevents traversal. Must be mounted **outside** `pipe_through :browser` (CSRF protection and `x-frame-options` break sandboxed iframes). Why a Plug route instead of `srcdoc`: cross-artifact relative paths work (HTML can load sibling JSON), binary artifacts can be downloaded, and content stays on disk.

**UI:** `OmniUI.Artifacts.PanelComponent` — self-contained LiveComponent receiving only `session_id` from the parent. Owns all artifact state (`@artifacts`, `@active_artifact`, `@content`, `@token`). AgentLive has zero artifact assigns. Communication via `send_update(PanelComponent, action: :rescan)` in `agent_event(:tool_result, ...)`. Index/detail single-view pattern. Rendering modes by MIME type: iframe preview (HTML, PDF), syntax-highlighted source (text types), markdown, media, and download.

**Inline chat components:** `Artifacts.ChatUI.tool_use/1` wraps the default `Components.tool_use/1`, adding command-specific content (filename buttons, status labels) via the `:aside` slot.

---

## Code Sandbox

An Elixir execution environment using per-execution `:peer` nodes. The agent sends code; the sandbox evaluates it, captures stdout and the return value, and returns both.

**Execution model:** Each invocation starts a fresh peer node, evaluates the code, and tears down. Clean slate every time — no state drift, and `Mix.install/1` (which can only run once per VM) works across invocations. Peer init requires explicit code path injection and Elixir boot (neither is automatic).

**IO capture:** StringIO process lives on the **host** node, set as group leader for the peer's eval process. Erlang distribution routes IO messages cross-node transparently. Host-local StringIO means partial output is always readable on timeout or peer crash.

**Tool:** `OmniUI.REPL.Tool` — schema accepts `title` (active-form description) and `code` (Elixir string). Dynamic `description/1` switches between dev (Mix.install available) and release (host deps only) guidance. Extension descriptions appended automatically.

**Sandbox-artifact bridge:** `OmniUI.REPL.SandboxExtension` behaviour — `code/1` returns AST or string evaluated in the peer, `description/1` returns a fragment for the tool description. `OmniUI.Artifacts.REPLExtension` injects a top-level `Artifacts` module into the peer with `write`, `read`, `patch`, `list`, `delete` — delegating to `FileSystem` with session opts baked in.

**Inline chat component:** `REPL.ChatUI.tool_use/1` replaces the default renderer entirely — terminal icon, agent-provided title in the toggle, syntax-highlighted Elixir code instead of raw JSON params.

**Security:** Personal-use tool, not a secure multi-tenant sandbox. Peer crash isolation and configurable timeout, but no filesystem jailing, resource limits, or network restrictions.

---

## Tool Lifecycle

OmniUI does not auto-register tools. The developer adds them explicitly in LiveView callbacks.

Artifact and REPL tools need a `session_id` (from `handle_params`), so they're created together in a `create_tools/1` helper called from `handle_params/3`. `mount/3` calls `start_agent/2` with `tool_timeout: 120_000` (the default 5s is too short for sandbox execution). On session switch, `handle_params` replaces all tools with the new session_id via `update_agent/2`.

AgentLive's `agent_event(:tool_result, %{name: tool_name}, socket) when tool_name in ["artifacts", "repl"]` triggers `send_update(PanelComponent, action: :rescan)`. This lives in AgentLive, not the macro — tooling is application-level, not framework-level.
