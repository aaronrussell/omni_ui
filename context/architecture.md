# Architecture Decisions

Decisions made during the Phase 1 build-out of the chat UI. This supplements `vision.md` — where they conflict, this document takes precedence.

---

## Source of Truth

The app owns conversation state. `OmniUI.Tree` is the authoritative store — a branching tree of messages held in the LiveView's assigns. The `Omni.Agent` GenServer is a downstream consumer: before each prompt the app syncs the agent's context to match the tree via `Omni.Agent.set_state/3`. This ensures that after edits, regenerations, or branch switches the agent always works with the correct message history.

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

## Naming: AgentLive + chat_interface

- **`OmniUI.AgentLive`** — the mountable LiveView. The batteries-included "just give me an agent" entry point. Wires up the agent, manages the tree, includes artifacts panel.
- **`chat_interface/1`** — function component composing the message stream, streaming turn, and editor. The reusable chat UI that doesn't care what drives it.

"Agent" is the product (tools, artifacts, the works). "Chat" is the UI pattern (messages, editor, streaming). A developer who wants the full package mounts `AgentLive`. A developer who wants just chat in their own LiveView uses `chat_interface/1`.

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
└── artifacts panel (future)
```

**Two LiveComponents:**

- **`TurnComponent`** — renders a completed turn from the `:turns` stream. Owns inline editing state (textarea input, edit mode toggle) and handles copy-to-clipboard. Forwards `navigate` and `regenerate` events to the parent via `phx-click`; sends `{:edit_message, turn_id, message}` to the parent on edit submit.
- **`EditorComponent`** — owns composition state (textarea input, file uploads via `allow_upload/3`). Supports click-to-attach and drag-and-drop. On submit, base64-encodes files into `Omni.Content.Attachment` structs, builds an `Omni.Message`, and sends `{:new_message, message}` to the parent. High-frequency keystroke and upload state stays isolated from the parent.

**The streaming turn is a function component**, not a LiveComponent. The LiveView keeps `@current_turn` in its assigns and renders it with the same `turn/1` component used inside `TurnComponent`. LiveView's change tracking means only the template block referencing `@current_turn` re-evaluates on each delta — the stream of completed turns is untouched. The DOM diff sent over the wire is small (just appended text).

If streaming performance becomes an issue, two non-architectural fixes are available: debouncing deltas (batch on a 50-100ms timer), or deferring markdown rendering to the client via a JS hook.

---

## Streaming Architecture

1. **User submits** → `EditorComponent` sends `{:new_message, message}` → `AgentLive` pushes message to tree, prompts agent, sets `@current_turn` (with `status: :streaming`)
2. **Agent streaming events** → `handle_info` updates `@current_turn` via `Turn.push_content/2`, `push_delta/2`, `put_tool_result/2`
3. **Agent `:done`** → pushes all response messages to tree → computes `edits`/`regens` from tree children → builds completed turn via `Turn.new/3` → `stream_insert(:turns, turn)` → clears `@current_turn`
4. **Agent `:error`** → `stream_insert` the current turn with `status: :error` → clears `@current_turn`

Streaming state is determined by `@current_turn != nil` — no separate boolean flag.

LiveView's change tracking ensures only the `@current_turn` portion of the template re-evaluates on each delta. The stream of completed turns is not re-rendered.

---

## Editing and Regeneration

Both operations create new branches in the tree.

**Editing a user message:**

1. `TurnComponent` sends `{:edit_message, turn_id, message}` to parent
2. `AgentLive` navigates tree to the **parent** of the edited message (so `push_node` creates a sibling)
3. Pushes new user message → new branch from the same parent
4. Syncs agent context to tree messages *before* the new user message
5. Prompts agent with new content, resets `:turns` stream

**Regenerating a response:**

1. `AgentLive` receives `"regenerate"` event with `turn_id`
2. Navigates tree so head = the user message node (new response branches from here)
3. Syncs agent context to tree messages *before* the user message
4. Prompts agent with original user content, resets `:turns` stream

Both flows end with the same streaming lifecycle: `@current_turn` accumulates deltas, `:done` pushes the completed turn to the stream.

**Branch switching** uses `Tree.navigate/2` + `Tree.extend/1` to set the new active path, then recomputes all turns via `Turn.all/1` and resets the stream with `stream(:turns, turns, reset: true)`.

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
