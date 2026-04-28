# Session Pivot — Handover

This document briefs a Claude Code agent working in the `omni_agent` codebase on a significant architectural addition: `Omni.Session`. The design was worked out in conversation in the `omni_ui` repo before deciding that `omni_agent` is the right home. This doc is the full handoff.

---

## Why this is happening

`omni_ui` is a LiveView chat kit built on `Omni.Agent`. It's working, but the architecture has a creaking seam: the LiveView owns conversation state (message tree, persistence, session routing) and syncs it into the Agent on every prompt. That made sense when we started but has accumulated complexity:

- Session switching means cancel-in-flight-agent + reset-tree + rebuild-tools + push_patch — a multi-step dance coordinated across subsystems.
- You can't leave a session running when switching away — you must `Omni.Agent.cancel/1`.
- Session-scoped component ids exist purely to work around tree-node-id collisions between sessions' assigns.
- Tools that need a session_id (artifacts, REPL) are thrown away and rebuilt on every switch.
- Persistence logic lives in the UI layer but is really a session-state concern.

Every one of these is a tell: we're simulating "session-as-process" without actually having a process per session.

**The pivot:** introduce `Omni.Session` — a durable, supervised process that owns session state (message tree, metadata, persistence) and wraps an inner `Omni.Agent`. Sessions live across UI disconnects. Multiple subscribers can view one session. Sessions can stream in the background while the user browses elsewhere. On reopen, subscribers get a snapshot of current state (including in-flight streaming) plus a live feed of subsequent events.

The net effect on `omni_ui`: it shrinks substantially. A LiveView subscribes to a Session and mirrors its state. No local tree state, no persistence plumbing, no session-switch dance.

---

## What you're building in `omni_agent`

### The two-process model

```
LiveView (or any consumer) ──subscribe──▶ Omni.Session ──listener──▶ Omni.Agent
                             ◀─events───              ◀─events──
```

- **`Omni.Agent`** stays as it is — a streaming-compute GenServer. Don't modify it unless a specific integration point needs it.
- **`Omni.Session`** is a new GenServer. Each active session is one Session process. It holds tree + metadata + subscribers + current-turn streaming state, and supervises an inner `Omni.Agent` (linked, same lifetime).
- Session and Agent always live and die together. When the Session terminates (idle, explicit close, or crash), the Agent terminates with it. Starting a Session starts an Agent.

### Lifecycle

- `Omni.Session.open(id, opts)` is find-or-start: looks up `id` in a `Registry`; returns the pid if found, else starts a new Session via `DynamicSupervisor`. Loads persisted state in `init/1` if a store is configured.
- Sessions terminate when an idle timer fires AND there are no subscribers AND no turn is streaming ("don't terminate while cooking" is a headline feature).
- Reopening a terminated session is just another `open/1` call — starts a fresh process, loads from persistence. No special "rehydrate from memory" path.
- Crashes: v1 uses `restart: :temporary`. A crashed Session isn't auto-restarted; the next `open/1` starts fresh. Partial streaming state is lost; committed state survives. Document this explicitly.

### Subscriber / catchup protocol

- `Session.subscribe(pid)` returns `{:ok, snapshot}` where `snapshot` includes `{id, tree, metadata, current_turn, status}`. Then the subscriber's mailbox receives `{:session, pid, event, data}` messages for every subsequent event.
- Multi-subscriber: Session holds a MapSet, broadcasts to each. Each subscriber is `Process.monitor`ed so dead ones are dropped automatically.
- Mid-turn catchup: if a subscriber joins while the Session is streaming, the snapshot includes the partial `current_turn`. The subscriber renders the snapshot identically to how it would render a from-scratch stream — no gap, no duplication.

### Event prefix

Subscribers receive `{:session, pid, event, data}` — **not** `{:agent, pid, event, data}`. Three reasons:

1. The pid belongs to the Session process, not the inner Agent. Emitting `{:agent, ...}` with a Session pid would be mislabeling.
2. Sessions emit events Agents don't: `:tree_updated` (after navigate/edit/regenerate), `:metadata_updated` (model/title/etc changes).
3. Consumers may use both a Session and a raw Agent in the same LiveView. Distinct prefixes = distinct `handle_info` clauses, no conflation.

### Tree (branching message history)

Each session owns a branching tree of messages. This is the durable conversation data. Tree ops: `push`, `navigate`, `extend`, `children`, `messages` (flatten active path).

A tree with no branches is a degenerate flat list — no overhead for consumers that never branch. Don't make the tree opt-in; the general case subsumes the linear case.

Session operations that mutate the tree:
- `prompt/2` — append user message, sync agent context, prompt agent
- `edit/3` — navigate to the parent of an existing user message, push a sibling user message (new branch), re-prompt
- `regenerate/2` — navigate to a user message, push a new sibling assistant response, re-prompt
- `navigate/2` — switch active path to a different node (uses cursors to extend to a leaf)

After mutation, the Session emits `{:session, pid, :tree_updated, tree}` so subscribers can re-render.

### Persistence

Pluggable via a behaviour (port the existing `OmniUI.Store` — it's well-designed). Configuration:

```elixir
config :omni, Omni.Session.Store, adapter: Omni.Session.Store.FileSystem
```

With no adapter configured, save functions no-op. That gives ephemeral sessions for free — useful for tests, demos, kiosks, privacy-mode flows.

Session persists:
- Tree — on `:done` (after each completed turn). Incremental append to tree.jsonl.
- Metadata — on change (model/title/thinking updates). Full rewrite; it's small.

Session doesn't persist tools (handlers aren't serializable) or runtime config. The caller provides tools fresh on every `open/1`.

### Tools

Tools are passed to `Session.open/2` (or mutated via `Session.add_tools/remove_tools`), and the Session hands them straight through to its inner Agent. The Session doesn't inspect, track, or persist tools — just forwards.

Stateful tools (ones that need a session_id at construction) still take it at construction from the caller. The caller also knows the session_id (it's the first arg to `open/1`) so passing it twice is fine — no magic injection.

Past tool *calls* (`ToolUse` + `ToolResult` blocks) are part of message history, which IS persisted. Current tool set is runtime config.

### Storage layering

Session storage and tool storage are separate concerns coordinated by convention:

```
{base}/sessions/{id}/tree.jsonl      ← Session adapter
{base}/sessions/{id}/meta.json       ← Session adapter
{base}/sessions/{id}/artifacts/*.*   ← (OmniUI's Artifacts tool, not your concern)
```

Don't design a generic "put file" API in the Session store. Adapter should expose high-level ops tied to session state (save_tree, save_metadata, load, list, delete). Non-filesystem backends (Ecto, S3) implement those without getting dragged into filesystem semantics. Tools that need storage handle their own storage.

---

## Public API sketch

This is a shape, not a spec. Names and exact signatures are for you to refine.

```elixir
# Lifecycle
{:ok, pid} = Omni.Session.open(id, opts)
                   # opts: [:model, :tools, :system, :thinking, :tool_timeout, :store, ...]
:ok        = Omni.Session.close(pid)                    # explicit; idle timer is normal path
{:ok, sessions} = Omni.Session.list(opts)               # persistence-backed
:ok        = Omni.Session.delete(id)                    # terminate if alive + wipe persistence

# Subscription
{:ok, snapshot} = Omni.Session.subscribe(pid)
:ok             = Omni.Session.unsubscribe(pid)

# Operations
:ok = Omni.Session.prompt(pid, message_or_string)
:ok = Omni.Session.navigate(pid, node_id)
:ok = Omni.Session.edit(pid, turn_id, message)
:ok = Omni.Session.regenerate(pid, turn_id)
:ok = Omni.Session.cancel(pid)
:ok = Omni.Session.update(pid, opts)                    # model, thinking, tools, system, title
:ok = Omni.Session.add_tools(pid, tools)
:ok = Omni.Session.remove_tools(pid, names)

# Inspection
{:ok, value} = Omni.Session.get(pid, field)             # :tree | :metadata | :status | ...
```

Events (arrive as `{:session, session_pid, event, data}` messages):

```elixir
# Forwarded from the inner agent (streaming)
:text_delta, :text_start, :text_end
:thinking_delta, :thinking_start, :thinking_end
:tool_use_start, :tool_use_delta, :tool_use_end
:tool_result
:done, :error, :cancelled, :retry
:pause  (tool approval pattern)

# Emitted by the session itself
:tree_updated        # after navigate/edit/regenerate or :done
:metadata_updated    # after update/2 changes
```

---

## Phases

Build and test incrementally. Don't wire this up to omni_ui during these phases — that's a separate workstream after all four are done.

### Phase 1: Session process foundation (no tree, no persistence)

**Scope.** `Omni.Session` GenServer that wraps an `Omni.Agent`. Linear message history (just uses the agent's context). DynamicSupervisor + Registry + `open/1`. Subscriber protocol with snapshot + broadcast. Idle termination. `prompt`, `cancel`, `subscribe`, `unsubscribe`.

This is the architectural novelty. Once this works, everything else is additive.

**Public API in this phase:**

```elixir
Omni.Session.open(id, model: ..., system: ..., tools: ...)
Omni.Session.subscribe(pid)
Omni.Session.unsubscribe(pid)
Omni.Session.prompt(pid, message)
Omni.Session.cancel(pid)
Omni.Session.close(pid)
```

Snapshot shape (minimal):

```elixir
%{
  id: "abc",
  messages: [%Omni.Message{}, ...],   # from inner agent's context
  current_turn: %{...} | nil,          # partial streaming state, or nil when idle
  status: :idle | :streaming
}
```

Event prefix `{:session, pid, event, data}` already.

**Tests.**
- `open/2` starts a process; calling again with same id returns same pid.
- `open/2` with different ids gives different pids.
- `subscribe/1` returns a snapshot; caller then receives events.
- Multi-subscriber: both get events; dead subscribers are dropped (use `Process.monitor`; test with a spawned process that exits).
- Mid-turn catchup: start a session, prompt, subscribe mid-stream (easiest way: stub the agent's HTTP with a slow stream via `Omni`'s `:plug` option). Assert snapshot contains partial `current_turn` and subsequent deltas arrive without duplication.
- Idle termination: session with no subscribers terminates after the timer (make the timer configurable so tests can set it to ~50ms).
- Cooking: session mid-turn with no subscribers does NOT terminate; stays up until `:done`.
- `prompt/2` routes to inner agent; agent events are forwarded as session events.
- `cancel/1` routes to agent; `:cancelled` is emitted.
- Linked lifetime: terminating the session terminates the agent (use `Process.alive?/1` to verify).

**Out of scope in this phase.** Trees, persistence, metadata updates, tools mutation. `prompt` pushes to a flat message list (whatever shape the inner Agent already uses).

### Phase 2: Branching tree

**Scope.** Port `OmniUI.Tree` into the session (see `/Users/aaron/Dev/ai/omni_ui/lib/omni_ui/tree.ex`). Session owns the tree. `navigate/2`, `edit/3`, `regenerate/2` APIs. Session syncs the agent's context messages from the active path on every operation.

**Public API additions:**

```elixir
Omni.Session.navigate(pid, node_id)
Omni.Session.edit(pid, turn_id, message)
Omni.Session.regenerate(pid, turn_id)
```

Snapshot shape updated to include the tree:

```elixir
%{
  id: ...,
  tree: %Omni.Session.Tree{...},   # replaces :messages
  current_turn: ...,
  status: ...
}
```

New event: `{:session, pid, :tree_updated, tree}` emitted after any tree mutation (including `:done`, since that pushes response messages onto the tree).

**Port considerations.**
- `OmniUI.Tree` is self-contained — nodes, path, cursors. Copy the module, change the namespace.
- `OmniUI.Tree.messages/1` extracts the active path as a message list — used to sync the agent's context.
- The `Omni.Codec` round-tripping already works (tree nodes ↔ JSON via codec). Keep it.

**Tests.**
- `prompt/2` pushes user message to tree, syncs agent context, prompts.
- On `:done`, response messages push onto the tree. `:tree_updated` emitted.
- `navigate/2` updates active path, emits `:tree_updated`, agent context mirrors new path.
- `edit/3` creates a sibling under the parent, not a child of the target. New branch visible via `children/2`. Emits `:tree_updated`.
- `regenerate/2` creates a sibling assistant under the user message. Emits `:tree_updated`.
- Branching preserved: after edit + regenerate, tree has all branches; navigate back restores old path.
- Tree mutations while agent is streaming: pick a policy — either queue or reject with a clear error. Test whichever you choose.

### Phase 3: Persistence

**Scope.** Port `OmniUI.Store` behaviour and `OmniUI.Store.FileSystem` adapter (see `/Users/aaron/Dev/ai/omni_ui/lib/omni_ui/store.ex` and `/Users/aaron/Dev/ai/omni_ui/lib/omni_ui/store/`). Session persists tree on `:done`, metadata on change. `init/1` loads from store. `list/0` and `delete/1` operate through the store.

**Public API additions:**

```elixir
Omni.Session.list(opts)        # persistence-backed
Omni.Session.delete(id)        # terminate if alive + wipe persistence
```

**Port considerations.**
- Behaviour is 5 callbacks: `save_tree`, `save_metadata`, `load`, `list`, `delete`.
- FileSystem adapter uses JSON (meta.json) and JSONL (tree.jsonl for incremental append). Keep this format — it's stable and debuggable.
- Config shape: `config :omni, Omni.Session.Store, adapter: Omni.Session.Store.FileSystem`. No-op when unconfigured.
- The existing `OmniUI.Store` includes a nice "surface_save_error" pattern — adapters return `{:ok, ...} | {:error, term()}` and callers surface errors non-fatally. Preserve this.

**Tests.**
- Round-trip: save tree + metadata, terminate session, reopen with same id — state restored.
- `list/0` returns all persisted sessions; pagination (`:limit`, `:offset`) works.
- `delete/1` removes on-disk state. If process is alive, also terminates it.
- No-op adapter: configure no adapter; open/save/close work but nothing persists.
- Save errors: adapter returns `{:error, _}`. Session doesn't crash. Test the caller-visible API.
- Incremental save: appending new nodes to an existing tree only appends to tree.jsonl, doesn't rewrite.

### Phase 4: Metadata, tool updates, lenient model resolution

**Scope.** `update/2` for model/thinking/tools/system/title. Metadata persistence. Emit `:metadata_updated` events. Port lenient model resolution (unresolvable model ref → log, keep current, don't crash).

**Public API additions:**

```elixir
Omni.Session.update(pid, opts)           # keyword: :model, :thinking, :tools, :system, :title
Omni.Session.add_tools(pid, tools)
Omni.Session.remove_tools(pid, names)
```

**Port considerations.** See `OmniUI.update_agent/2` in `/Users/aaron/Dev/ai/omni_ui/lib/omni_ui.ex` — the options, lenient model handling, and tool list normalization are already worked out. Main changes: emit `:metadata_updated` events after mutations, call store to persist metadata changes.

**Tests.**
- `update(pid, model: ...)` syncs to agent, emits event, persists metadata.
- `update(pid, tools: ...)` swaps tools on the agent.
- `update(pid, title: nil)` is an explicit clear (not a no-op).
- Lenient: unresolvable model ref doesn't crash; logs; keeps current model.
- Tool list normalization handles both `%Omni.Tool{}` and `{%Omni.Tool{}, opts}` shapes.

---

## Reference files in omni_ui

You have read access to the full `omni_ui` codebase at `/Users/aaron/Dev/ai/omni_ui/`. Files worth studying:

**Port candidates (copy + rename namespace):**
- `lib/omni_ui/tree.ex` — the branching tree. Self-contained. Port for phase 2.
- `lib/omni_ui/store.ex` — Store behaviour + public module. Port for phase 3.
- `lib/omni_ui/store/file_system.ex` — filesystem adapter with JSON/JSONL format. Port for phase 3.

**Study for patterns (don't port directly):**
- `lib/omni_ui.ex` — `start_agent/2`, `update_agent/2`, tool normalization, lenient model resolution. Useful as a reference for phase 4.
- `lib/omni_ui/handlers.ex` — how agent events are currently handled and accumulated into `@current_turn`. The current-turn accumulation logic moves into the Session in phase 1/2.
- `lib/omni_ui/agent_live.ex` — `start_new_session/2` logic, session routing. Useful for understanding the current model — and for sensing how much will simplify after the pivot.

**Context:**
- `context/architecture.md` — current design (pre-pivot). Reference for how things work today.
- `context/roadmap.md` — where the project is in its overall trajectory.

**Don't port these (they're UI concerns):**
- `lib/omni_ui/turn.ex` — rendering views over the tree; stays in omni_ui.
- `lib/omni_ui/components.ex`, `*_component.ex` — UI components.
- `lib/omni_ui/notification.ex` — UI toaster.
- `lib/omni_ui/title.ex` — could arguably move later, but stay out for now.

---

## Testing strategy

- **Use `Req.Test` plugs to stub HTTP** for agent interactions. See the Omni skill doc and Omni's own test suite. No real LLM calls in tests.
- **Integration tests at the Session level** are the most valuable — they exercise the full Session + Agent + Store stack end-to-end with stubbed HTTP.
- **Unit tests for the tree module** separately — pure data, no process involved. Fast.
- **Process lifecycle tests** should use short idle timeouts (configurable per-start) so tests don't wait seconds.
- **Async safety**: use `start_supervised` in tests to ensure cleanup. Don't rely on manual `stop` calls.

Target: every phase ends with the test suite green and reasonable coverage on the new public API.

---

## Out of scope for the omni_agent work

Explicitly not yours:
- Any changes to `omni_ui`. That's a follow-up workstream.
- Moving artifacts or REPL tools into omni_agent. They stay in omni_ui for now.
- Title generation. Stays in omni_ui.
- UI components, notifications, turn rendering.

If `Omni.Agent` needs small tweaks to support Session integration (e.g., a hook, a new option), make them — but keep the Agent lean. Don't push session-specific concepts into it.

---

## Plan first, then implement

Before writing code, read the reference files and produce a short plan document in `omni_agent` covering:
- Module layout (where `Omni.Session`, `Omni.Session.Server`, `Omni.Session.Tree`, `Omni.Session.Store` etc. will live)
- State struct shape for the Session
- Snapshot struct shape
- Supervisor tree (how users add `Omni.Session.Supervisor` and `Omni.Session.Registry` to their application)
- Event type catalog (full list of `{:session, pid, event, data}` shapes)
- Any open questions worth flagging before implementation

Discuss the plan with the user before starting phase 1.

---

## Expected cleanup in omni_ui afterwards

For future reference — not your concern during the omni_agent work, but flagging so nothing is lost:

**Remove / replace:**
- `lib/omni_ui/tree.ex` → gone (moved to `Omni.Session.Tree`)
- `lib/omni_ui/store.ex` + `lib/omni_ui/store/*` → gone (moved)
- The `@tree` socket assign and all tree-mutation code paths
- `@current_turn` local accumulation in `OmniUI.Handlers` → becomes "mirror Session's current_turn from events"
- `start_agent/2` → becomes `start_session/2` (or similar) — opens a Session, subscribes, applies snapshot
- `update_agent/2` → delegates to `Omni.Session.update/2`
- `handle_info` clauses for `{:agent, ...}` → become `{:session, ...}`
- `OmniUI.Handlers.handle_agent_event/3` → much of this moves to the Session; handlers just translate session events to assigns
- `AgentLive.start_new_session/2` → simplifies hugely (just `Session.open(new_id)` + subscribe)
- Persistence-related code throughout `AgentLive` (`surface_save_error`, `save_tree`/`save_metadata` calls) → gone
- `handle_params/3` load-existing branch → just subscribe to a session
- Session-scoped `TurnComponent` ids workaround → may still be needed; re-evaluate

**Keep:**
- All components (`components.ex`, `turn_component.ex`, `editor_component.ex`, `sessions_component.ex`)
- `Turn` struct and `Turn.all/1` — still computes rendering views from a tree
- Title generation and `handle_async` wiring
- Notifications system
- Artifacts and REPL tools
- CSS theming

**Integration pattern** (rough):

```elixir
# mount / handle_params
{:ok, session_pid} = Omni.Session.open(session_id,
  model: default_model,
  tools: create_tools(session_id))
{:ok, snapshot} = Omni.Session.subscribe(session_pid)

# Apply snapshot to socket (tree, metadata, current_turn, status)
```

Switching sessions becomes `unsubscribe` from the old, `open + subscribe` on the new. Old session keeps running if it's mid-turn — the "cooking" feature lights up automatically.

**Expected doc updates:**
- `context/architecture.md` — large rewrite (the "Source of Truth", "Streaming Architecture", "Persistence", "Sessions" sections).
- `context/roadmap.md` — update status; the Persistence workstream note about Store being standalone becomes obsolete.
- README / hex docs — new "Session" concept.

This cleanup is probably a week of focused work after the omni_agent side lands, but a lot of it is deletion, which makes it faster than it sounds.
