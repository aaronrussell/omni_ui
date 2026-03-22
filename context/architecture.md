# Architecture Decisions

Decisions made during the Phase 1 build-out of the chat UI. This supplements `vision.md` — where they conflict, this document takes precedence.

---

## Data Structure: Turns

The UI stores a stream of `OmniUI.Turn` structs, not a flat list of messages.

Each turn represents one user prompt + one complete agent response (which may include multiple internal LLM roundtrips with tool calls). The `OmniUI.Turn` struct is a **rendering-optimized** transformation of `Omni.Turn` — it pre-separates user text from attachments, flattens all assistant content blocks into a single list, and collects tool results into a map.

**Why turns over flat messages:**

- **Branching.** Turns have `id` and `siblings`. Editing a user message or regenerating a response creates a sibling turn. With flat messages, branching requires reconstructing turn-like grouping ad hoc.
- **Self-contained rendering.** A turn component has everything it needs — user content, assistant content, tool results, usage, timestamps. No cross-message lookups.
- **Clean streaming.** `@current_turn` accumulates during a round. On completion, one `stream_insert` adds the finished turn. No coordinating multiple stream entries.
- **Error recovery.** A failed turn keeps the user message visible with an error state and retry button. The user message is never lost.

**Branch navigation:** Use `stream(:turns, new_path, reset: true)` to replace the stream when switching branches. No splice needed — branch switches are infrequent, and resetting a stream of tens of turns is negligible.

---

## OmniUI.Turn Struct

```elixir
defstruct [
  :id,
  :error,
  :user_timestamp,
  :timestamp,
  status: :complete,
  siblings: [],
  user_text: [],
  user_attachments: [],
  content: [],
  tool_results: %{},
  usage: %Omni.Usage{}
]
```

- **`user_text`** / **`user_attachments`** — pre-separated from the user message content. Components receive exactly what they render.
- **`content`** — all assistant content blocks (Thinking, Text, ToolUse) accumulated from all intermediate assistant messages in the turn.
- **`tool_results`** — `%{tool_use_id => %ToolResult{}}` extracted from intermediate user messages.
- **`status`** — `:complete | :streaming | :error`. Replaces separate boolean flags.
- **`error`** — error reason string when `status == :error`.
- **`user_timestamp`** — from the user's message (`DateTime.t()`).
- **`timestamp`** — from the last assistant message in the turn. `nil` while streaming.
- **`siblings`** — list of sibling turn IDs for branch navigation.

`Turn.from_omni/2` converts `Omni.Turn` → `OmniUI.Turn`, performing all filtering and flattening. Helper functions `push_content/2`, `push_delta/2`, and `put_tool_result/2` handle streaming accumulation. Components never touch `Omni.Turn` directly.

---

## Naming: AgentLive + chat_interface

- **`OmniUI.AgentLive`** — the mountable LiveView. The batteries-included "just give me an agent" entry point. Wires up the agent, manages tools, includes artifacts panel.
- **`chat_interface/1`** — function component composing the message stream, streaming turn, and editor. The reusable chat UI that doesn't care what drives it.

"Agent" is the product (tools, artifacts, the works). "Chat" is the UI pattern (messages, editor, streaming). A developer who wants the full package mounts `AgentLive`. A developer who wants just chat in their own LiveView uses `chat_interface/1`.

---

## Component Structure

```
AgentLive (LiveView)
├── chat_interface/1 (function component)
│   ├── Stream of turn/1 (function component)
│   │   ├── user_message/1 (function component)
│   │   │   ├── text content blocks
│   │   │   └── attachment/1 tiles (shared component, read-only)
│   │   └── assistant_message/1 (function component)
│   │       ├── content_block/1 (pattern-matched function component)
│   │       │   ├── text block
│   │       │   ├── thinking block
│   │       │   └── tool_use block (with paired tool_result)
│   │       ├── error display + retry (when status == :error)
│   │       └── per-turn usage
│   │
│   ├── turn/1 for @current_turn (function component, visible while streaming)
│   │   ├── user_message/1
│   │   └── assistant_message/1 (same components, streaming indicators)
│   │
│   └── MessageEditor (LiveComponent)
│       ├── textarea + submit button
│       ├── drag-drop zone (phx-drop-target)
│       ├── attachment previews (using shared attachment/1 component)
│       │   └── cancel button per entry (via :action slot)
│       ├── attach button (label wrapping hidden live_file_input)
│       └── toolbar slots
│
└── artifacts panel (future)
```

**One LiveComponent — `MessageEditor`** — justified by state isolation. It owns composition state (textarea input, file uploads via `allow_upload/3`), supports click-to-attach and drag-and-drop, and on submit base64-encodes files into `Omni.Content.Attachment` structs, builds an `Omni.Message`, and sends it to the parent. High-frequency keystroke and upload state stays isolated from the parent.

**The streaming turn is a function component**, not a LiveComponent. The LiveView keeps `@current_turn` in its assigns and renders it with the same `turn/1` component used for completed turns. LiveView's change tracking means only the template block referencing `@current_turn` re-evaluates on each delta — the stream of completed turns is untouched. The DOM diff sent over the wire is small (just appended text).

If streaming performance becomes an issue, two non-architectural fixes are available: debouncing deltas (batch on a 50-100ms timer), or deferring markdown rendering to the client via a JS hook.

---

## Streaming Architecture

The LiveView keeps `@current_turn` in its assigns. Streaming events update this assign directly via `handle_info`:

1. User submits → parent sets `@current_turn` (with `status: :streaming`), prompts agent
2. Agent streaming events → `handle_info` updates `@current_turn` via `Turn.push_content/2`, `push_delta/2`, `put_tool_result/2`
3. Agent `:done` → `stream_insert` the completed turn (from `Turn.from_omni/2`), clear `@current_turn`
4. Agent `:error` → `stream_insert` the current turn with `status: :error`, clear `@current_turn`

Streaming state is determined by `@current_turn != nil` — no separate boolean flag.

LiveView's change tracking ensures only the `@current_turn` portion of the template re-evaluates on each delta. The stream of completed turns is not re-rendered.

---

## Error Handling

When the agent errors during a turn:

1. Push the turn to the stream with `status: :error` and the error message
2. The turn component renders the user message normally + error state where the assistant response would be + a retry button
3. Retry re-prompts the agent; on success, `stream_insert` replaces the errored turn (same ID)

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
