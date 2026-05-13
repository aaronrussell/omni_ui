# OmniUI — Package Design

This is the single reference for how `omni_ui` is built. It covers the
package end-to-end at the level of detail needed to work inside it
without rediscovering the design from code.

`CLAUDE.md` complements this document with developer conventions and
workflows, but defers to this file for architecture. For the upstream
session/agent/store/manager mechanics this package consumes, see
`../omni_agent/context/design.md`.

---

## 1. What this package is

OmniUI is a Phoenix LiveView component kit for building agent chat
interfaces on top of [`omni_agent`](https://github.com/aaronrussell/omni_agent).
It does not own conversation state — `Omni.Session` does. OmniUI's job
is to render a session, route UI events into session operations, and
provide a small library of shipped tools that live well inside the
chat UI (files, an Elixir REPL, and web fetching — powered by
`omni_tools`).

The package is layered. Each layer is independently consumable:

```
OmniUI.AgentLive       — mountable LiveView. Wires header, sessions
                         drawer, files panel, Files+REPL+WebFetch
                         tools, and the chat interface.
       │
use OmniUI             — macro. Adds session-streaming plumbing,
                         state ownership, and event handling to any
                         LiveView. Public API: init_session/2,
                         attach_session/2, ensure_session/1,
                         update_session/2, notify/2,3.
       │
OmniUI.Components      — pure function components. Layer 1 building
                         blocks: chat_interface, message_list, turn,
                         user_message, assistant_message, content_block,
                         tool_use, attachment, toolbar, notifications,
                         session_list, expandable, version_nav, etc.
```

**Source of truth.** `Omni.Session` (in `omni_agent`) owns the
branching tree, persistence, idle-shutdown, and the linked
`Omni.Agent`. The LiveView is a *subscriber*: it receives
`{:session, pid, event, data}` messages, mirrors session state into
assigns, and renders. There is no local tree-mutation path; all writes
go through `Omni.Session.{prompt, navigate, branch, set_title,
set_agent}`.

---

## 2. Relationship to `omni` and `omni_agent`

`omni_ui` depends on:

- **`omni_tools`** — ready-to-use agent tools. `Omni.Tools.Files`
  (file CRUD), `Omni.Tools.Repl` (sandboxed Elixir execution),
  `Omni.Tools.WebFetch` (URL fetching). `AgentLive.Agent` configures
  and wires these at agent init time. OmniUI does not implement its
  own tools.
- **`omni`** — stateless LLM client. Provides `Omni.Model`,
  `Omni.Message`, `Omni.Content.{Text, Thinking, ToolUse, ToolResult,
  Attachment}`, `Omni.Tool`, `Omni.Usage`, and the `generate_text`
  call used by `OmniUI.Title`.
- **`omni_agent`** — stateful agent + session + manager + store. The
  primary integration surface:
  - `Omni.Session` — subscribed-to per LiveView; events arrive as
    `{:session, pid, type, payload}` and translate directly to assign
    mutations in `OmniUI.Handlers`.
  - `Omni.Session.Tree` — pure data, mirrored into the `:tree` assign.
    `OmniUI.Turn.all/1` and `Turn.get/2` operate on it.
  - `Omni.Session.Manager` — `OmniUI.Sessions` is a thin `use
    Omni.Session.Manager` subclass under the `:omni_ui` otp_app.
    Consumers add it to their supervision tree with a configured store.
  - `Omni.Session.Snapshot` and `Omni.Agent.Snapshot` — applied to
    socket assigns on attach (`apply_snapshot/4` in `OmniUI`).
  - `Omni.Session.Store.FileSystem` — referenced by config (consumers
    pass it to `OmniUI.Sessions`); uses `:base_dir` for the absolute
    storage path.

**What lives where.** Persistence, idle shutdown, branching mechanics,
and tool execution are all `omni_agent` concerns. OmniUI does not
implement persistence, run tools, or compute the tree — it observes,
displays, and dispatches. Where this document references those
concepts (e.g. "the session emits `:tree` after every mutation"), the
canonical spec is in `../omni_agent/context/design.md`.

---

## 3. The `use OmniUI` macro

The macro is the primary integration point. A consumer writes `use
OmniUI`, implements `render/1` and `mount/3` (calling
`init_session/2`), wires `handle_params/3` to call
`attach_session/2`, and gets streaming, branching, persistence
mirroring, notifications, and event handling injected automatically.

### 3.1 Usage shape

```elixir
defmodule MyApp.ChatLive do
  use Phoenix.LiveView
  use OmniUI

  def mount(_params, _session, socket) do
    {:ok, init_session(socket, model: {:anthropic, "claude-sonnet-4-5"})}
  end

  def handle_params(params, _uri, socket) do
    if connected?(socket) do
      try do
        {:noreply, attach_session(socket, id: params["session_id"])}
      rescue
        _ -> {:noreply, push_patch(socket, to: "/")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl OmniUI
  def agent_event(:turn, {:stop, response}, socket) do
    MyApp.Analytics.track(response.usage)
    socket
  end

  def agent_event(_event, _data, socket), do: socket
end
```

### 3.2 What the macro injects

`__using__/1` registers `@before_compile` and imports
`OmniUI.Components` plus the public OmniUI API (`init_session/2`,
`attach_session/2`, `ensure_session/1`, `update_session/2`,
`notify/2,3`).

`__before_compile__/1` injects:

- `handle_event("omni:" <> _, ...)` — routes namespaced events to
  `OmniUI.Handlers.handle_event/3`.
- `handle_info({OmniUI, :new_message, _}, ...)`,
  `{OmniUI, :edit_message, _, _}`, `{OmniUI, :notify, _}`,
  `{OmniUI, :dismiss_notification, _}` — component-bubbled messages
  routed to `OmniUI.Handlers.handle_info/2`.
- `handle_info({:session, pid, event, data}, ...)` — the session
  event dispatcher. Drops events from a session we've since detached
  from (pid mismatch with `socket.assigns.session`), then runs
  `OmniUI.Handlers.handle_agent_event/3` and finally calls the
  consumer's `agent_event/3` callback.
- A default `agent_event(_event, _data, socket), do: socket` if the
  consumer doesn't define one.

Coexistence with consumer-defined handlers uses
`@before_compile` + `defoverridable`: OmniUI clauses are tried first,
and unrecognised events fall through via `super`.

### 3.3 Public API

#### `init_session/2`

Initialises every OmniUI-owned assign and stream. Called once from
`mount/3`. Sets:

- Agent config: `:manager`, `:agent_module`, `:model`, `:thinking`,
  `:system`, `:tools`, `:tool_timeout`, `:tool_components`.
- Session state: `:session` (pid or nil), `:session_id`, `:title`,
  `:tree`, `:current_turn`, `:usage`, `:url_synced`,
  `:notification_ids`.
- Streams: `:turns` (completed turns, dom-id `turns-...`),
  `:notifications`.

The session is `nil` after `init_session/2` — it's attached either
by `attach_session/2` (on `handle_params`) or by `ensure_session/1`
(lazily, on first `:new_message`). Mounting `/` does not spawn a
session.

Options of note:

- `:model` (required) — `%Omni.Model{}` or `{provider, id}` tuple.
- `:manager` — Manager module (default `OmniUI.Sessions`).
- `:agent_module` — module that `use`s `Omni.Agent`. The session
  starts the agent under this module, so its `init/1` callback can
  bake in tools, system prompt, etc.
- `:tools` — list of tool entries. Each entry is `%Omni.Tool{}` or
  `{%Omni.Tool{}, opts}` where `opts[:component]` is a 1-arity
  function component overriding the default tool-use renderer.
- `:tool_components` — map of `tool_name => component_fun` for tools
  the consumer doesn't construct (typically tools added by the
  `:agent_module`'s `init/1`). Merged with components extracted from
  `:tools`; this map wins on conflicts.
- `:tool_timeout` — per-tool execution timeout in ms.

#### `attach_session/2`

Called from `handle_params/3`. Three behaviours:

- `id: nil` (or omitted) — detaches any current session and resets
  to the blank state. Sessions are lazily created later by
  `ensure_session/1`, so refreshing on `/` does not pile up
  untitled drafts.
- `id: id == socket.assigns.session_id` — no-op. Idempotency for
  `push_patch` to the same URL.
- `id: id` — detaches the previous session (releases the
  `:controller` hold so it can idle-shutdown), opens the new
  session via `manager.open(id, subscribe: false, ...)`, then
  `Omni.Session.subscribe(pid, mode: :controller)` atomically pairs
  subscribe with the snapshot. Raises if the id isn't found in the
  store — wrap in `try/rescue`.

The previous-session detach calls `Omni.Session.unsubscribe/1`
inside a `try/catch` so a dead-or-missing prior session doesn't
crash the new attach.

#### `ensure_session/1`

Used by the macro's `:new_message` handler. If `:session` is `nil`,
creates a fresh session via `manager.create(subscribe: false, ...)`
and subscribes the LiveView as `:controller`. If a session is
already attached, returns the socket unchanged.

The split between `create` (fresh) and `open` (existing) matters:
`create` generates a new id; `open` looks up an existing one. That
distinction is owned by the Manager, not OmniUI.

#### `update_session/2`

Updates session/agent configuration on a running system. Accepts a
keyword list with any subset of `:model`, `:thinking`, `:system`,
`:tools`. For each option:

- `:model` — calls `Omni.get_model/2` to resolve. On
  `{:error, _}`, logs a warning and pushes a notification but does
  not raise (a session whose persisted model has been deregistered
  still loads). `start_session`-time resolution stays strict — it
  raises on failure.
- `:thinking` — updates assign + session agent opts.
- `:system` — updates session agent system prompt.
- `:tools` — runs `normalise_tools/1`, updates assign +
  `:tool_components`, swaps tools on the session agent.

When called before a session is attached, only the assigns update.
Values get passed to the session at `ensure_session/1` time.

`maybe_set_agent/3` is the bridge: `is_pid(pid)` →
`Omni.Session.set_agent(pid, key, value)`; otherwise no-op.

#### `notify/2,3`

In-process toaster. `notify(level, message, opts)` does
`send(self(), {OmniUI, :notify, %Notification{}})`. Levels:
`:info | :success | :warning | :error`. Default timeout 20s.
Imported via the macro, so it's in scope from anywhere in the
LiveView (LiveComponents whose `self()` is the parent LV
process; library code running inside the LV; async callbacks).

No PubSub, no registry — strictly in-process v1.

### 3.4 The `agent_event/3` callback

Fires for every session event after OmniUI's default handling, with
the already-mutated socket. Receives the session-event tag (e.g.
`:turn`, `:tree`, `:store`, `:state`, `:status`, `:title`,
`:text_delta`, `:tool_use_end`, `:tool_result`, `:error`, etc.) and
its payload. Must return a socket.

Naming oddity: events arrive in `{:session, ...}` tuples but the
callback is `agent_event/3`. Renaming to `session_event/3` is on the
polish list.

---

## 4. State ownership and lifecycle

### 4.1 OmniUI-owned assigns

| Assign | Purpose |
|---|---|
| `:manager` | Module implementing `Omni.Session.Manager` |
| `:agent_module` | Optional `Omni.Agent` callback module |
| `:model` | Resolved `%Omni.Model{}` |
| `:thinking` | `false \| :low \| :medium \| :high \| :max` |
| `:system` | System prompt or nil |
| `:tools` | Flat `[%Omni.Tool{}]` |
| `:tool_components` | `%{name => component_fun}` |
| `:tool_timeout` | Per-tool timeout ms |
| `:session` | Session pid or nil |
| `:session_id` | Binary id or nil |
| `:title` | Title string or nil |
| `:tree` | `%Omni.Session.Tree{}` mirror |
| `:current_turn` | `%OmniUI.Turn{}` while streaming, else nil |
| `:usage` | Cumulative `%Omni.Usage{}` from `Tree.usage/1` |
| `:url_synced` | `:store {:saved, _}` URL-patch latch |
| `:notification_ids` | FIFO order list (cap = 5) |
| `@streams.turns` | Completed turns |
| `@streams.notifications` | Active toasts |

Consumers own everything else (model option lists, view-toggle
booleans, custom event handlers).

The rule for consumers: if `mount/3` is setting an OmniUI-owned
assign directly, reach for `init_session/2` instead.

### 4.2 The lifecycle

```
mount/3
  └─ init_session/2 — assigns set, session: nil, streams initialised

handle_params/3
  ├─ id: <binary>     → attach_session/2 → manager.open + subscribe
  ├─ id: nil          → attach_session/2 → blank state
  └─ id: same_as_now  → no-op

EditorComponent submit
  └─ {OmniUI, :new_message, message}
       └─ Handlers.handle_info → ensure_session/1 → Omni.Session.prompt
            (lazy session creation if none attached)

session events {:session, pid, type, data}
  └─ macro handle_info → Handlers.handle_agent_event → agent_event/3
```

### 4.3 The "blank session" / lazy-create pattern

Sessions are not created on mount or on `/?session_id=`. The user
opens `/`, the LV initialises with `:session = nil`. On the first
`:new_message`, `ensure_session/1` calls `manager.create/1`, which
generates an id and starts the session under the
DynamicSupervisor. Subsequent prompts reuse the now-set `:session`.

This avoids untitled draft sessions piling up on page refreshes,
and gives the lazy creation path a natural place to call —
`ensure_session/1` runs inside the `:new_message` handler, in the
LiveView process, so the subscription is `mode: :controller`.

### 4.4 URL synchronisation

The first time the session writes anything to disk
(`:store {:saved, _}` event), the `Handlers.handle_agent_event/3`
clause for `:store` patches the URL to `?session_id=<id>` and sets
`:url_synced = true`. The latch prevents repatching on subsequent
saves.

This is the signal that the session id is real and worth bookmarking
— before the first save, the session exists in memory only and
might idle-shut without ever persisting.

### 4.5 Session detach race-handling

When `attach_session/2` switches sessions, queued events from the
old session may still be in the LV mailbox. The macro's
`handle_info({:session, pid, ...})` clause checks
`pid == socket.assigns[:session]` and silently drops mismatches.
Without this, a stale `:tree` event could clobber the new session's
state.

The detach also calls `Omni.Session.unsubscribe/1` on the old
session, releasing the `:controller` hold so it can idle-shutdown.
Wrapped in `try/catch :exit, _` for the case where the old session
is already gone.

---

## 5. Event handling

`OmniUI.Handlers` is a private module containing pure
event/info/session-event dispatch. The macro routes to it; the
module returns `{:noreply, socket}` (for `handle_event`/`handle_info`)
or just a socket (for `handle_agent_event`).

### 5.1 UI events (`handle_event/3`)

Routed by the `"omni:" <> _` prefix:

| Event | Effect |
|---|---|
| `omni:select_model` | `update_session(model: ...)` |
| `omni:select_thinking` | `update_session(thinking: ...)` |
| `omni:dismiss_notification` | Stream-deletes the toast |
| `omni:navigate` | `Omni.Session.navigate/2` |
| `omni:regenerate` | `Omni.Session.branch/2` (regen) |

`omni:navigate` and `omni:regenerate` map directly to
`Omni.Session` calls. Errors come back as
`{:error, :busy | :paused | :not_found | _}` — handled by the
private `notify_branch_error/1` helper which surfaces an appropriate
toast and logs the unknown cases.

### 5.2 Component-bubbled messages (`handle_info/2`)

| Message | Effect |
|---|---|
| `{OmniUI, :new_message, msg}` | `ensure_session` + `Session.prompt` + set `current_turn` |
| `{OmniUI, :edit_message, turn_id, msg}` | `Session.branch(parent_id, content)` (target = parent assistant) |
| `{OmniUI, :notify, notification}` | Stream insert + FIFO eviction at cap = 5 |
| `{OmniUI, :dismiss_notification, id}` | Stream delete |
| `{OmniUI, :active_session_deleted}` | Caught in AgentLive — `push_patch` to `/` |

**Edit semantics.** `{OmniUI, :edit_message, turn_id, message}` — the
sender is `TurnComponent`, the `turn_id` is the *user* node being
edited. Per `Omni.Session.branch/3`, branching from an assistant pushes
a new user+assistant pair as its children, so we look up
`tree.nodes[turn_id].parent_id` (the assistant above the edited user)
and pass that as the target. Edits at the root (parent_id = nil)
become disjoint root branches. This is opposite-asymmetric from the
old tree-owns-state model, where edit navigated to the user's parent
and pushed a sibling user.

Both `:new_message` and `:edit_message` set `:current_turn` to a
streaming-status turn built from the user's content with `id: nil` —
the user node id isn't known until the session emits `:tree` with
`new_nodes` populated. `adopt_current_turn_id/2` patches it in.

### 5.3 Session events (`handle_agent_event/3`)

Receives the `event` atom and `data` payload from
`{:session, pid, event, data}` after the pid filter.

**Streaming deltas** accumulate into `@current_turn`:

- `:thinking_start`, `:text_start` → `Turn.push_content/2` with empty
  block.
- `:thinking_delta`, `:text_delta` → `Turn.push_delta/2`.
- `:tool_use_end` → `Turn.push_content/2` with the completed
  `%ToolUse{}`.
- `:tool_result` → `Turn.put_tool_result/2`.

**Turn boundary.** `:turn`:

- `{:stop, _}` → `current_turn: nil`. The `:tree` event that follows
  carries the committed nodes; the rebuilt turn list will include the
  just-finished turn.
- `{:continue, _}` → keep `current_turn`. Continuations are multiple
  agent turns concatenated into one UI turn.

**Tree mirror.** `:tree` with `%{tree: tree, new_nodes: [...]}`:

- `adopt_current_turn_id/2` patches the in-flight `current_turn.id`
  if it's still nil. The first non-empty `new_nodes` after streaming
  starts has the user node at the head — adopting it lets the rebuild
  filter the in-flight turn out by id.
- Rebuild turns from `Turn.all(tree)`, reject the in-flight turn,
  reset the `:turns` stream with `reset: true`. Update `:tree` and
  `:usage` assigns.

The reject-by-id is what prevents the streaming `current_turn` and
the rebuilt completed turn from both rendering during the brief
window between commit and `current_turn: nil`. Navigates and
mid-branch resyncs send `:tree` with `new_nodes: []` — same code
path, just no in-flight turn to reject.

**Persistence acks.** `:store`:

- `{:saved, _kind}` — first time, patches URL (see § 4.4).
- `{:error, kind, reason}` — logs at `:error`, notifies the user.

**Title changes.** `:title` → `assign(:title, ...)`. Triggered by
`Omni.Session.set_title/2` from the consumer or by `OmniUI.TitleService`
asynchronously (see § 7).

**Agent state sync.** `:state` mirrors model and `opts[:thinking]`
into assigns. Defensive — explicit `update_session/2` paths already
keep these aligned, but a `set_agent` from another process (e.g. a
future Manager-level update) would otherwise leave the LV stale.

**`:status`** is currently a no-op clause; the LV doesn't yet surface
busy/idle distinctions in chrome.

**Errors.** `:error` logs, notifies, and stream-inserts the
`current_turn` with `status: :error` so the user message is
preserved with an error-shaped assistant slot. The user message is
never lost.

### 5.4 Notifications

`OmniUI.notify/2,3` sends `{OmniUI, :notify, %Notification{}}` to
`self()`. The handler:

1. Schedules `Process.send_after(self(), {OmniUI, :dismiss_notification, id}, timeout)`.
2. Appends the id to `:notification_ids`.
3. Splits at the cap (5). Evicted ids are stream-deleted.
4. Stream-inserts the new notification at position 0.

Manual dismiss + auto-dismiss timer race is idempotent —
`stream_delete` on a missing id and `List.delete` on a missing
element are both no-ops.

---

## 6. Tree consumption and the `OmniUI.Turn` view

The session's tree is one node per message — assistant, user, and
tool-result messages are all separate nodes. UI rendering wants
*turns*: one user prompt + any tool-use rounds + the final assistant
response, presented as one unit. `OmniUI.Turn` is that projection.

### 6.1 Struct

```elixir
%OmniUI.Turn{
  id:                node_id(),         # user node id
  res_id:            node_id() | nil,   # first assistant node id
  status:            :complete | :streaming | :error,
  user_text:         [%Omni.Content.Text{}],
  user_attachments:  [%Omni.Content.Attachment{}],
  user_timestamp:    DateTime.t() | nil,
  content:           [Text | Thinking | ToolUse],   # assistant
  timestamp:         DateTime.t() | nil,
  tool_results:      %{tool_use_id => %ToolResult{}},
  error:             String.t() | nil,
  usage:             %Omni.Usage{},
  edits:             [node_id()],        # sibling user nodes (incl. self)
  regens:            [node_id()]         # sibling assistant nodes (incl. self)
}
```

`edits` and `regens` always include the active node (`id` in `edits`,
`res_id` in `regens`). UI components compute position with
`OmniUI.Helpers.sibling_pos/2` (`"2/3"`) and draw prev/next nav from
the lists directly.

### 6.2 Building turns

Three constructors:

- `Turn.all/1` — walks the tree's active path, chunks at user-message
  boundaries (skipping tool-result users), and builds a turn from
  each chunk. Used to rebuild the `:turns` stream on every `:tree`
  event.
- `Turn.get/2` — walks forward from a given node id to the next turn
  boundary, building a single turn. Used in scenarios that want one
  turn back from a node id (currently not on the live event path,
  but available — e.g. for future multi-step continuation rebuilds).
- `Turn.new/3` — builds a turn from raw messages + cumulative usage.
  Used in `apply_snapshot/4` to reconstruct a streaming turn from the
  agent's `pending` + `partial` messages when subscribing mid-stream.

### 6.3 Streaming accumulators

`Turn.push_content/2`, `Turn.push_delta/2`, and `Turn.put_tool_result/2`
mutate the in-flight turn during streaming. They live on `Turn` rather
than on `Handlers` because they're pure data ops with non-trivial
shape (e.g. `push_delta` updates the *last* content block's `:text`
field).

### 6.4 Mid-stream catchup

`apply_snapshot/4` is called from `attach_session/2`. When the
snapshot includes an in-flight turn (`snapshot.agent.pending != []`),
it builds a streaming `Turn` via `Turn.new/3` over
`pending ++ List.wrap(partial)`. Subsequent streaming events from the
session then accumulate into this turn naturally.

---

## 7. Component architecture

### 7.1 Layer 1 — `OmniUI.Components`

All function components, no state. Public exports:

- **Layout.** `chat_interface/1`, `message_list/1`, `turn/1`.
- **Messages.** `user_message/1`, `assistant_message/1`,
  `user_message_actions/1`, `assistant_message_actions/1`.
- **Content blocks.** `content_block/1` (pattern-matched on
  `Text/Thinking/ToolUse/Attachment`), `tool_use/1` (default
  renderer), `markdown/1`, `attachment/1`.
- **UI primitives.** `expandable/1`, `version_nav/1`, `timestamp/1`,
  `usage_block/1`, `toolbar/1`, `select/1`, `notifications/1`,
  `session_list/1`.

`chat_interface/1` is the root wrapper. Provides the scroll
container, a mounted `OmniUI.EditorComponent`, optional `:toolbar`
and `:footer` slots, and the markdown typography styles via a class
list returned by `OmniUI.Helpers.md_styles/0`. Consumers compose
their own template inside this.

### 7.2 The two LiveComponents

- **`OmniUI.TurnComponent`** — renders one completed turn. Owns the
  inline-edit textarea state. On submit, sends
  `{OmniUI, :edit_message, turn_id, message}` to the parent. Forwards
  `omni:navigate` and `omni:regenerate` via plain `phx-click`
  (no `phx-target`, so they bubble to the LV).
- **`OmniUI.EditorComponent`** — owns the textarea input, drag-drop
  zone (`phx-drop-target`), and `allow_upload(:attachments, ...)`.
  On submit, base64-encodes attachments and sends
  `{OmniUI, :new_message, %Omni.Message{}}` to the parent. Accepts a
  `:toolbar` slot.

LiveComponents isolate high-frequency state (textarea keystrokes,
upload progress) from the parent.

### 7.3 The streaming turn is a function component

`@current_turn` is rendered in the LV's template via the same
`turn/1` function component used inside `TurnComponent` — *not* a
LiveComponent. LiveView's change tracking ensures only the
`@current_turn` block re-evaluates on each delta; the stream of
completed turns is untouched. The DOM diff is just appended text.

### 7.4 Component hierarchy under `AgentLive`

```
AgentLive (LiveView)
├── SessionsComponent (LiveComponent — left sidebar, permanently mounted)
│   └── session_list/1 (with :actions slot)
│
├── header/1 (private — top bar with sessions toggle, title, artifacts toggle)
│
├── chat_interface/1
│   ├── message_list/1
│   │   └── stream :turns
│   │       └── TurnComponent (per turn)
│   │           ├── turn/1 (user_message + assistant_message)
│   │           ├── user_message_actions/1
│   │           └── assistant_message_actions/1
│   │
│   ├── turn/1 for @current_turn (streaming)
│   ├── EditorComponent (rendered inside chat_interface)
│   ├── :toolbar slot → toolbar/1
│   └── :footer slot
│
├── Artifacts.PanelComponent (LiveComponent — right sidebar)
│
└── notifications/1 (stream :notifications)
```

The header is currently private to `AgentLive`. It will likely move
into `OmniUI.Components` so consumers building their own LV can use
it without recreating the title-edit + sessions-toggle plumbing.

### 7.5 Session-scoped TurnComponent ids

Tree node ids are per-session integer counters: every session has a
`turns-1`, `turns-2`, etc. If a `TurnComponent`'s id matched the
stream dom_id, switching sessions would reuse component instances
keyed by `(module, id)` and leak state across sessions (e.g. an
artifact button's filename, an edit-mode toggle).

The fix: wrap each TurnComponent in a div carrying the stream's
dom_id (satisfying `phx-update="stream"`), but key the component id
on the session node id only. AgentLive uses `id={"turn-#{turn.id}"}`
because resetting the `:turns` stream on session switch
(`stream(:turns, turns, reset: true)`) tears the components down
anyway. A previous version used `"#{session_id}:#{turn.id}"` — kept
in mind as the more defensive shape if subtle leaks reappear.

`stream_configure/3` doesn't help here — it's called once at mount
and the session id isn't known until `attach_session/2`.

---

## 8. Custom tool-use components

Per-tool custom rendering of `ToolUse` content blocks.

### 8.1 Registration

Tool entries to `init_session/2` (or `update_session/2`) accept two
shapes:

```elixir
%Omni.Tool{}                              # default rendering
{%Omni.Tool{}, component: fun}            # custom rendering
```

`OmniUI.normalise_tools/1` (public, undocumented for testing) splits
the list into a flat `[%Omni.Tool{}]` (handed to the agent) and a
`%{name => fun}` map (assigned to `:tool_components`). The
keyword-list shape on the tuple is forward-compatible — sibling keys
like `:title`, `:icon`, `:result_block` can be added without
breaking call sites.

For tools added by an `:agent_module`'s `init/1` callback (so
`init_session/2` never sees them), pass a `:tool_components` map
directly. It merges with the extracted-from-`:tools` map and wins on
key conflicts.

### 8.2 Propagation

`@tool_components` is threaded through:
`AgentLive` → `TurnComponent` → `assistant_message/1` →
`content_block/1`. The `ToolUse` clause of `content_block/1` looks up
the tool by name; on hit it calls the registered function, on miss
falls back to `tool_use/1`.

### 8.3 Assigns contract

Custom components receive a normalised assigns map:

- `@tool_use` — the `%Omni.Content.ToolUse{}` struct.
- `@tool_result` — the matching `%Omni.Content.ToolResult{}` or `nil`,
  pre-resolved from `:tool_results` so custom components don't repeat
  the lookup.
- `@streaming` — boolean.

`@tool_components` and the full `@tool_results` map are deliberately
not leaked into custom components.

### 8.4 Event handling

Custom components can include interactive elements. Without
`phx-target`, events bubble up through the TurnComponent to the
parent LiveView, where the consumer handles them in their own
`handle_event/3`. AgentLive uses this for the artifact "view"
button (`open_artifact` event).

### 8.5 Sharp edge

`@tool_components` is captured at `stream_insert` time per
TurnComponent. Hot-swapping tools mid-session via `update_session/2`
won't update already-rendered turns. In practice, tools are set
during `init_session/2` (from `:tool_components`) and fixed for the
session, so this doesn't bite. If mid-session swaps become a use
case, reset the `:turns` stream after the swap.

---

## 9. Branching UI flow

The three branching operations expose `Omni.Session` semantics with
appropriate UI pre-state.

| Action | Sender | Translation |
|---|---|---|
| Switch branches | `omni:navigate` (phx-click bubbled from TurnComponent) | `Omni.Session.navigate(session, node_id)` |
| Regenerate | `omni:regenerate` (phx-click bubbled) | `Omni.Session.branch(session, turn_id)` (regen, target = user node) |
| Edit user message | `{OmniUI, :edit_message, turn_id, msg}` (sent from TurnComponent on submit) | `Omni.Session.branch(session, parent_assistant_id, content)` |

For regen and edit, the handler sets `:current_turn` to a streaming
turn *before* the session emits its first event — so the UI shows
the new prompt immediately rather than briefly going blank. For
regen, the user content is fetched from the existing tree node; for
edit, it's the message the component just sent.

The `push_event(socket, "omni:updated", %{})` after each operation
is a hook for client-side scroll-to-bottom or similar — the JS side
listens for the event.

Branch errors (`{:error, :busy | :paused | :not_found | _}`) come
back from `Omni.Session` synchronously; `notify_branch_error/1` maps
them to user-friendly toasts.

---

## 10. Sessions

### 10.1 `OmniUI.Sessions` — the default Manager

```elixir
defmodule OmniUI.Sessions do
  use Omni.Session.Manager, otp_app: :omni_ui
end
```

Consumers add it to their supervision tree with a configured store:

```elixir
# config/dev.exs
sessions_dir = Path.expand("priv/omni/sessions")

config :omni_ui, :sessions_base_dir, sessions_dir

config :omni_ui, OmniUI.Sessions,
  store: {Omni.Session.Store.FileSystem, base_dir: sessions_dir}

# application.ex
children = [OmniUI.Sessions, ...]
```

Start-time opts override app-env values. Consumers wanting multiple
Managers (multi-tenant isolation, per-workspace) define their own
`use Omni.Session.Manager` modules and pass them via the `:manager`
option to `init_session/2`.

### 10.2 `OmniUI.SessionsComponent` — the drawer

A LiveComponent rendering a left-sidebar list of sessions. Receives
`current_id` and `manager` from the parent. State:

- `:sessions` — merged list of persisted sessions (`manager.list/0`)
  and currently-running ones (`manager.list_open/0`). Sorted: open
  first, then by `updated_at` descending.
- `:confirming_delete` — id of a session showing the inline two-step
  delete confirm.

Manager events (`{:manager, _, :opened | :status | :title | :closed,
_}`) don't reach LiveComponents directly — the parent LV catches
them in `handle_info/2` and forwards via:

```elixir
send_update(OmniUI.SessionsComponent, id: "sessions", manager_event: msg)
```

The component pattern-matches `update(%{manager_event: event}, ...)`
and folds the event into `:sessions`. Self-contained reduce
functions per event type (`:opened` upserts, `:status` updates,
`:closed` either marks dormant or removes the row, etc.).

Deleting the current session sends `{OmniUI, :active_session_deleted}`
to the parent — `AgentLive` listens for this and `push_patch`es to
`/`.

### 10.3 `OmniUI.TitleService` — auto-titling

A singleton GenServer that subscribes to a Manager and watches for
sessions opened without a title. When such a session emits
`:turn {:stop, _}`, the service:

1. Snapshots the session's tree (`Session.get_snapshot/1`).
2. Spawns a `Task.async` running `OmniUI.Title.generate(model, messages)`.
3. On success, calls `Omni.Session.set_title/2`.
4. On failure, logs and keeps the subscription open so the next
   `:stop` retries.

Subscribes in `:observer` mode — does not pin sessions open. Tracks
sessions in `state.pending`, indexed by id. Deduplicates: only one
generation per session per turn cycle. Re-subscribes when a title
is cleared back to `nil` (re-enables auto-generation).

Configuration:

```elixir
config :omni_ui, OmniUI.TitleService,
  manager: OmniUI.Sessions,
  model: {:openai, "gpt-4.1-nano"}    # nil = heuristic
```

Add after the Manager in the supervision tree.

The decoupling from `AgentLive` is intentional. Pre-pivot, title
generation lived inside the LiveView and only ran while the user was
attached. The service runs server-side, so a session left cooking
in the background gets auto-titled regardless of who's watching.

### 10.4 The header bar

In `AgentLive`, `header/1` is a private function component:

- Sessions drawer toggle (currently a static button — the drawer is
  permanently mounted, no hide/show wiring yet).
- New-session button → `phx-click="new_session"` → `push_patch` to
  `/`.
- Inline-editable title input with `phx-blur` and `phx-submit`,
  styled to look like plain text via `field-sizing: content` and
  borderless chrome. Both events route to the same `save_title`
  handler. Empty string saves as `nil` (explicit clear, re-enables
  auto-titling).
- Artifacts panel toggle (placeholder — panel is currently always
  visible).

The header is a strong candidate to move into `OmniUI.Components`
as a public `header/1` once its API stabilises. Right now it's
specific to AgentLive's exact layout.

### 10.5 Title commit flow

`save_title` calls `Omni.Session.set_title(pid, title)`. The session
persists (via `save_state` in the store) and emits `:title`,
`OmniUI.Handlers` mirrors the title back into `@title`. No special
optimistic-update path — the session's own event drives the assign.

Empty-string → `nil` is the explicit clear; the `Omni.Session.Store`
contract treats `title: nil` as a real saved value, not an absence.
On the next `:turn {:stop, _}`, `OmniUI.TitleService` sees the
nil-titled session and re-enters the generation loop.

---

## 11. Title generation library

`OmniUI.Title.generate(model, messages, opts)` is a pure function.
Two strategies via a single entry point:

- **Heuristic** (`model: nil`) — picks the first message containing
  text content, extracts the text, normalises whitespace, truncates
  at a 50-char word boundary with an ellipsis. No LLM call.
- **Model** (`model: Omni.Model.ref()` or `%Omni.Model{}`) — formats
  the first four messages as a `User: ...\n\nAssistant: ...` block
  inside a `<conversation>` tag, prompts with a fixed system
  instruction asking for a 3-6 word title. Calls
  `Omni.generate_text/3` with `max_tokens: 50` and returns the
  trimmed response text.

Returns `{:error, :no_text}` when no message contains text content
(filters out pure-attachment messages, thinking, tool uses, tool
results). The model branch checks the same first-four window the
prompt uses — no spurious LLM calls on text-empty turns.

Used by `OmniUI.TitleService` from inside its async task. Available
to consumers wanting on-demand title generation (e.g. a "rename"
button).

---

## 12. Notifications

A kit-native toaster for transient in-app messages. Replaces flash
because flash is tied to mount/navigate; OmniUI needs to push to a
surface from session events, async callbacks, and library code (e.g.
`update_session/2`'s lenient model branch).

### 12.1 Shape

```elixir
%OmniUI.Notification{
  id:      integer(),                  # System.unique_integer([:positive])
  level:   :info | :success | :warning | :error,
  message: String.t(),
  timeout: non_neg_integer()           # default 20_000ms
}
```

### 12.2 Plumbing

- `notify/2,3` (imported via the macro) — `send(self(),
  {OmniUI, :notify, %Notification{}})`.
- `init_session/2` sets up `stream(:notifications, [])` and
  `:notification_ids = []`.
- Macro injects `handle_info` clauses for `{OmniUI, :notify, _}` and
  `{OmniUI, :dismiss_notification, _}`; the existing `omni:` event
  prefix routes the close-button click.
- `notifications/1` function component renders the bottom-right stack
  and is rendered explicitly by the consumer (AgentLive does this).
  If absent, notifications are still received and auto-dismissed but
  invisible.

### 12.3 FIFO cap and timer races

Hard-coded 5 visible notifications (`@notification_cap`). On insert,
if `length(:notification_ids) > cap` the oldest is `stream_delete`d.

Manual dismiss + auto-dismiss timer race: the timer's eventual
`stream_delete` is idempotent on a missing id, and `List.delete/2`
on a missing element is a no-op. No need to cancel timers on manual
dismiss.

### 12.4 Levels

Each level has a distinct border color and Lucide icon: info
(neutral), success (green check), warning (amber triangle), error
(red x-circle). Defined in `OmniUI.Components.notifications/1`.

---

## 13. Files (formerly Artifacts)

Files created by the agent, persisted in the session, viewable and
downloadable from a panel. Session-scoped. Not branch-aware —
navigating conversation branches does not rewind file state.
This is deliberate; replaying tool calls along the active path to
reconstruct file state is too complex for the value.

### 13.1 Tools — `omni_tools`

The file, REPL, and web-fetch tools come from the `omni_tools`
package. OmniUI does not implement its own tools — it configures and
wires the `omni_tools` implementations at agent init time.

`OmniUI.AgentLive.Agent.init/1` reads
`state.private.omni.session_id`, derives the files directory via
`OmniUI.Sessions.session_files_dir/1`, and appends three tools:

- `Omni.Tools.Files.new(base_dir: files_dir, nested: false)` — flat
  file CRUD scoped to the session's files directory.
- `Omni.Tools.Repl.new(extensions: [{Omni.Tools.Repl.Extensions.Files, fs: fs}])`
  — sandboxed Elixir execution with the Files extension injected so
  sandbox code can read/write files directly.
- `Omni.Tools.WebFetch.new()` — URL fetching with HTML-to-markdown.

### 13.2 Filesystem layout

`{sessions_base_dir}/{session_id}/files/{filename}`

The base dir is configured via `config :omni_ui, :sessions_base_dir`.
`OmniUI.Sessions` exposes `session_dir/1` and `session_files_dir/1`
helpers that derive paths from this config.

Co-locating files with session data means session deletion (via the
Manager's `delete/1` → `Store.FileSystem` `File.rm_rf`) naturally
cleans up files.

The `Omni.Tools.Files.FS` module (from `omni_tools`) handles all
filesystem operations. The `PanelComponent` and `Plug` construct
`FS` structs via `session_files_dir/1` — no OmniUI-specific
filesystem module exists.

### 13.3 HTTP serving — `Artifacts.Plug`

Sandboxed iframes (the default for HTML file preview) need a real
URL to hit, not `srcdoc`, so cross-file relative paths work
(an HTML file can `fetch('./data.json')`) and binaries can be
downloaded.

```elixir
forward "/omni_files", OmniUI.Artifacts.Plug
```

URL format: `/{prefix}/{token}/{filename}`. The token is a
`Phoenix.Token.sign(endpoint, salt, session_id)` — encodes the
session id, expires after 24h by default. The plug verifies the
token, resolves the path via `FS.resolve/2` (which validates against
traversal, null bytes, etc.), and `send_file`s.

Mount must be **outside** the `:browser` pipeline. CSRF protection
and `x-frame-options` break sandboxed iframes. CORS headers are set
explicitly because sandboxed iframes have origin `null` and
sub-resource fetches (e.g. JSON loaded by HTML) need them.
`content-disposition` is `inline` for browser-displayable types and
`attachment` for everything else.

`OmniUI.Artifacts.URL` is the signing/URL-construction helper —
`sign_token/2`, `verify_token/3`, `artifact_url/3`. URL prefix
defaults to `"/omni_files"`, configurable via
`config :omni_ui, OmniUI.Artifacts, url_prefix: "/your_prefix"`.

### 13.4 `Artifacts.PanelComponent`

A self-contained LiveComponent receiving only `session_id` from the
parent. Owns all file state (`:artifacts`, `:active_artifact`,
`:content`, `:token`, `:view`, `:view_source`, `:error`). Uses
`Omni.Tools.Files.FS` for scanning and reading files.

Two view modes:

- **Index** — list of files, click to open.
- **Detail** — a single file rendered per its media type.

Detail render modes:

- `:iframe` — `text/html` (sandboxed `allow-scripts`),
  `application/pdf`. Source is the Plug URL.
- `:markdown` — `text/markdown` via MDEx with the markdown typography
  styles.
- `:media` — `image/*` via `<img>` from the Plug URL.
- `:source` — `text/*`, `application/json`, and other text-likes via
  `Lumis.highlight!` syntax highlighting.
- `:download` — everything else, "Download" link.

HTML, Markdown, and SVG files support a Preview/Code toggle
(`view_source` boolean overrides the default).

Communication from parent: `send_update(PanelComponent, action: ...)`
— `:rescan` (called from `AgentLive.agent_event(:tool_result, ...)`)
or `{:view, filename}` (called when the user clicks an inline
file button in the chat). AgentLive holds zero file assigns.

### 13.5 Inline chat component — `Artifacts.ChatUI`

`tool_use/1` registered as the files tool's custom renderer. It
*wraps* `Components.tool_use/1` (the default expandable) and slots
command-specific content into the `:aside` slot — the default icon,
toggle, and raw input/output remain. The aside renders only after the
tool produces a result:

- `write` / `patch` — clickable filename button → `open_artifact`
  event → `AgentLive.handle_event` → `send_update(PanelComponent,
  action: {:view, filename})`.
- `read` / `delete` / `list` — short status label.

---

## 14. REPL and WebFetch

The REPL and WebFetch tools come from `omni_tools`. OmniUI
configures them in `AgentLive.Agent.init/1` and provides a custom
chat renderer for the REPL.

### 14.1 REPL configuration

`Omni.Tools.Repl` evaluates Elixir code in isolated peer nodes.
Each invocation is a clean slate. The agent wires it with the
`Omni.Tools.Repl.Extensions.Files` extension, which injects a
`Files` module into the sandbox peer so code can read/write session
files directly without a separate tool-use round-trip.

The extension receives the same `%Omni.Tools.Files.FS{}` struct
used by the Files tool, ensuring both operate on the same directory.

For execution model details (peer nodes, IO capture, timeouts,
distribution boot), see the `omni_tools` documentation.

### 14.2 Inline chat component — `REPL.ChatUI`

`tool_use/1` *replaces* the default renderer entirely (unlike
the files ChatUI which wraps it):

- Terminal icon instead of cog.
- Toggle shows the agent-provided `title` field instead of the
  literal tool name.
- Expanded body shows syntax-highlighted Elixir code (the `code`
  input field) instead of raw JSON params.
- Tool result formatted as JSON via `format_tool_result/1`.

### 14.3 WebFetch

`Omni.Tools.WebFetch` fetches URLs and converts HTML to markdown.
No custom ChatUI — uses the default tool-use renderer. No
OmniUI-specific configuration.

---

## 15. CSS theming

`priv/static/omni_ui.css` defines the visual theme using Tailwind 4's
`@theme` directive. Semantic tokens in OKLCH:

- `omni-bg`, `omni-bg-1`, `omni-bg-2` — background layers.
- `omni-text-1..4` — text emphasis (1 = strongest, 4 = muted).
- `omni-border-1..3` — border emphasis.
- `omni-accent-1`, `omni-accent-2` — interactive/accent.

Dark mode via `@variant dark`. Components use these tokens
exclusively (e.g. `text-omni-text-3`, `bg-omni-bg-1`), with
exceptions only for fixed-meaning colors (green/red/amber for
success/error/thinking states).

Consumers override the theme by redefining the CSS custom properties
(`--color-omni-*`). The `.omni-ui` class on the root
`chat_interface` element scopes the component tree.

**Markdown typography** is defined as Tailwind descendant-selector
classes (`[&_.mdex_*]`) returned by `OmniUI.Helpers.md_styles/0`.
Applied at `chat_interface` (and `Artifacts.PanelComponent`) root,
they target the `.mdex` class MDEx applies to rendered HTML. This
keeps the `markdown/1` component's markup minimal while defining
typography once.

---

## 16. Module layout

```
lib/
  omni_ui.ex                       # macro + init/attach/ensure/update + notify
  omni_ui/
    agent_live.ex                  # mountable LiveView (Layer 3)
    agent_live/
      agent.ex                     # custom Omni.Agent: wires Files, Repl, WebFetch
    components.ex                  # Layer 1 function components
    editor_component.ex            # textarea + uploads (LiveComponent)
    handlers.ex                    # private — event/info/session-event dispatch
    helpers.ex                     # cls, format_*, time_ago, md_styles, to_md, etc.
    notification.ex                # %Notification{}
    sessions.ex                    # OmniUI.Sessions — default Manager + dir helpers
    sessions_component.ex          # drawer (LiveComponent)
    title.ex                       # title generation (heuristic + model)
    title_service.ex               # singleton GenServer: auto-title untitled sessions
    tree_faker.ex                  # test fixture (uses Omni.Session.Tree)
    turn.ex                        # %OmniUI.Turn{} + Turn.all/1, Turn.get/2, Turn.new/3
    turn_component.ex              # rendering one turn (LiveComponent)
    artifacts/
      chat_ui.ex                   # inline tool-use renderer (files tool)
      panel_component.ex           # right-sidebar panel (LiveComponent)
      panel_ui.ex                  # function components for the panel
      plug.ex                      # signed-token HTTP serving
      url.ex                       # token signing + URL construction
    repl/
      chat_ui.ex                   # inline tool-use renderer (repl tool)
priv/static/omni_ui.css            # OKLCH theme + markdown typography
omni_ui_dev/                       # companion Phoenix app for browser testing
test/                              # ExUnit suite
```

Public modules carry `@moduledoc` with examples. `OmniUI.Handlers`
is `@moduledoc false` (private dispatch).

The companion app at `omni_ui_dev/` is the consumer reference. It
wires `OmniUI.Sessions` and `OmniUI.TitleService` into the
supervision tree, configures the FileSystem store, mounts
`OmniUI.Artifacts.Plug` at `/omni_files`, and routes `/` to
`OmniUI.AgentLive`.
