# Handover — Session.Manager workstream

You are picking up `omni_ui` mid-migration. This file is a self-contained
brief: read it before touching code. Where it disagrees with
`context/architecture.md` or `context/roadmap.md`, **trust this doc** —
the architecture/roadmap docs are stale post-pivot and need rewriting at
the end of this workstream.

The companion doc you should also read once is `context/session_pivot.md`
— that's the original handover that drove an architectural pivot in the
upstream `omni_agent` package. It explains the *why*. This doc explains
*where we are now* and *what's next*.

---

## The pivot in one paragraph

`omni_ui` used to own conversation state itself: an `OmniUI.Tree` in the
LiveView's assigns, a pluggable `OmniUI.Store` for persistence, and the
LiveView orchestrated everything. That model accumulated complexity
around session switching, tools-needing-session-id, and "leave a session
running and come back". Upstream, `omni_agent` introduced
`Omni.Session` — a GenServer that wraps an `Omni.Agent`, owns the
branching message tree, owns persistence, and emits a unified event
stream. `omni_ui` is now a *consumer* of `Omni.Session`: the LiveView
mirrors session state and renders, nothing more.

`omni_agent` is a path dependency at `../omni_agent`. It already ships
`Omni.Session`, `Omni.Session.Tree`, `Omni.Session.Store` (+ FileSystem
adapter), `Omni.Session.Snapshot`, and `Omni.Session.Manager`. The
manager is *the next thing we integrate*; everything else is in place.

---

## What's done (HEAD = `223fb25`)

**Stripped:**

- `lib/omni_ui/tree.ex` — gone (replaced by `Omni.Session.Tree`)
- `lib/omni_ui/store.ex` + `lib/omni_ui/store/file_system.ex` — gone
  (replaced by `Omni.Session.Store` + `Omni.Session.Store.FileSystem`)
- All persistence hooks in `AgentLive` — `surface_save_error/1`,
  `start_async(:generate_title)`, `save_metadata`, `save_tree`, `Store`
  alias — gone. Persistence is now session-driven.

**Reshaped:**

- `lib/omni_ui.ex` (the macro): `start_agent/2` → `start_session/2`,
  `update_agent/2` → `update_session/2`. The `ui_event/3` callback is
  gone — persistence is automatic now, so consumers don't need to
  observe macro-handled UI events. The injected `handle_info` clause
  matches `{:session, _, _, _}` instead of `{:agent, _, _, _}`.
- `lib/omni_ui/handlers.ex`: rewritten around session events. New
  clauses for `:tree`, `:store`, `:title`, `:state`, `:status`. `:turn`
  with payload `{:stop, _}` or `{:continue, _}` replaces the old
  `:stop` event. **Branching ops are commented out, not deleted** —
  navigate/regenerate/edit_message bodies sit in comment blocks with a
  pointer to which `Omni.Session` API will replace them.
- `lib/omni_ui/agent_live.ex`: slim. Mount + handle_params + render.
  No header, no sessions drawer, no artifacts panel, no title editing,
  no title generation. Reads its store from `config :omni,
  OmniUI.AgentLive, store: {Module, opts}`. Note the user added a
  call to `start_session/2` in mount/3 itself (in addition to
  handle_params) — this is intentional preparation for Manager
  integration; see "known waste" below.
- `lib/omni_ui/turn.ex`, `lib/omni_ui/tree_faker.ex`: alias swap from
  `OmniUI.Tree` to `Omni.Session.Tree`. The struct shape is identical.

**Stubbed (deliberately, will reintegrate):**

- `lib/omni_ui/sessions_component.ex`: file kept verbatim except the
  `Store.list/1` and `Store.delete/1` calls are stubbed (`page = []`,
  `:ok = :ok`) so the file compiles. Component is *unmounted* in
  `AgentLive.render/1`. The user explicitly asked to leave the markup
  intact for re-wiring later.
- `lib/omni_ui/artifacts/*` and `lib/omni_ui/repl/*`: untouched. Tools
  are not passed to the session. Panels not rendered. They'll be
  re-wired in a later workstream.
- `lib/omni_ui/title.ex`: untouched. No call sites — auto title
  generation was ripped out of `AgentLive`. The module is independent
  and can stay.

**Tests:**

- Deleted: `test/omni_ui/tree_test.exs`, `test/omni_ui/store/`.
- Skipped with `@moduletag :wip`: `test/omni_ui/macro_test.exs`
  (still references `start_agent`/`update_agent`; needs rewriting
  against the new shape).
- `test/test_helper.exs` excludes `:wip` by default.
- `mix test` is green: 255 passing, 18 `:wip`-skipped.

**Config:**

- `omni_ui_dev/config/config.exs`: `config :omni, OmniUI.Store, ...`
  and `config :omni, OmniUI.AgentLive, title_generation: ...` removed.
  Replaced with `config :omni, OmniUI.AgentLive, store:
  {Omni.Session.Store.FileSystem, base_path: "priv/sessions"}`.
- Wiped legacy session data at `omni_ui_dev/priv/omni/`. New data lives
  at `omni_ui_dev/priv/sessions/<id>/{nodes.jsonl, session.json}`.
- `mix.exs` (root): `omni "~> 1.3"`, `omni_agent` is a path dep at
  `../omni_agent`. `mix.lock` and `omni_ui_dev/mix.lock` updated.

---

## What works right now

Boot the dev app (`cd omni_ui_dev && mix phx.server`), hit `/`. You can:

1. Send a prompt; the response streams.
2. After the first turn commits the URL patches itself to
   `/?session_id=<auto-id>`.
3. Reload the page — conversation restores from disk.
4. Hit `/?session_id=does-not-exist` — graceful redirect to `/`.

## What's deliberately disabled (don't try to "fix")

- The sessions drawer (header button gone, component unmounted).
- The new-session button (gone).
- The title bar (gone).
- Edit-a-user-message, regenerate-a-response, branch navigation buttons
  on each `TurnComponent` — the buttons still render but the parent
  `handle_event`/`handle_info` clauses are commented out. Clicking them
  is a no-op (or shows a toast in the edit case).
- The artifacts panel toggle (gone). The `Artifacts.PanelComponent`
  still exists and is mountable; just not mounted from `AgentLive`.
- REPL and Artifacts tools — not passed to the session, so the agent
  can't call them.

## Known waste (Manager will fix)

- Mount calls `start_session/2` unconditionally; `handle_params/3`
  *also* calls `start_session/2`. Result: every page load creates 1–2
  orphan `Omni.Session` processes that get GC'd when the LV terminates.
  No disk writes happen on a fresh session until a turn commits, so
  there's no on-disk leakage — just RAM churn. **Manager's
  find-or-start lookup eliminates this**: mount becomes "look up by id
  (or assign new), get back a pid, subscribe".

---

## The next workstream — Session.Manager + sessions drawer

This is the architecturally biggest piece left. Doing it next is a
deliberate choice: it pays off the orphan-mount waste, unlocks the
sessions drawer, and unblocks the "leave a session cooking and come
back" UX. Branching, title, and tools are all small additive pieces
afterward.

**Don't start coding immediately.** First do a focused research +
planning pass, present a plan to the user, and only then implement.

### Phase A — Research

1. Read `../omni_agent/lib/omni/session/manager.ex` and the modules
   under `../omni_agent/lib/omni/session/manager/`. Answer:
    - How is the manager started (supervisor child spec, registry)?
    - What's `find_or_start`-style API actually called? What args?
    - What's the live-feed/pubsub story for "drawer wants to know when
      sessions are added/updated/deleted"?
    - Does the manager own session list state, or does it pass through
      to the store on every list? (This affects drawer pagination
      semantics.)
    - What's the lifecycle / idle-shutdown story when sessions are
      managed?
    - Does the manager handle "delete a session" (terminate + wipe
      persistence) or do we still call `Store.delete/2` directly?
2. Note `../omni_agent/CLAUDE.md` and `../omni_agent/context/` for any
   project conventions.
3. Skim `../omni_agent/test/` for usage examples — manager tests will
   show the canonical wiring shape.
4. Identify gaps: anything the drawer needs that Manager doesn't
   provide. If a gap blocks the work, file it (or flag it to the user)
   *before* writing the plan.

### Phase B — Plan

Write a plan covering:

- Where `Omni.Session.Manager` (and its registry/supervisor) get added
  to the dev app's supervision tree.
- How `OmniUI.AgentLive.mount/3` and `handle_params/3` change. Goal:
  no orphan sessions, no double-start. The shape is probably
  `Manager.find_or_start(id, opts)` (or similar) called once in
  `handle_params`, never in mount.
- How `OmniUI.SessionsComponent` re-mounts: which Manager calls
  replace `Store.list`/`Store.delete`. Whether the drawer subscribes
  to a "sessions changed" feed for live updates, or refreshes on open
  (current behaviour).
- The session-switch UX: parent unsubscribes from old session,
  subscribes to new, applies the new snapshot. Old session keeps
  running (or shuts down per Manager's idle policy).
- `handle_info({OmniUI, :active_session_deleted}, …)` and the
  "delete-current-session" flow against the new API.
- Whether mid-session URL switches (push_patch with new session_id)
  flow through `handle_params` or via a dedicated event.
- Test strategy. The macro tests can stay `:wip` for now; what
  *does* need coverage is the new Manager wiring (likely an
  integration test in `omni_ui_dev`).

Present the plan. Wait for approval. Then build.

### Phase C — Implement

Standard cycle: small steps, compile clean (`--warnings-as-errors`),
tests green, manual verify in browser, commit when stable. The user
manually tests in a browser (don't start the dev server yourself).

---

## After Manager — short list of follow-ups

Each is independent of the others; can be done in any order, and most
are small.

1. **Branching ops (navigate / regen / edit).** The handler bodies
   are sitting commented-out in `lib/omni_ui/handlers.ex`. Re-wire
   each to call the corresponding `Omni.Session` function:
    - `omni:navigate` → `Omni.Session.navigate/2`
    - `omni:regenerate` → `Omni.Session.branch/2` (target = user node
      id; reuses the user's content)
    - `{OmniUI, :edit_message, turn_id, message}` →
      `Omni.Session.branch/3` (target = parent assistant node id, new
      content). **Note the parent vs target asymmetry**: in the old
      tree-owns-state model, edit navigated to the user message's
      parent and pushed a sibling. With `Omni.Session.branch/3`, the
      target is the *assistant* and the new user+turn appends as
      children. Spec: `../omni_agent/lib/omni/session.ex` moduledoc.
   The session emits `:tree` events with `new_nodes: []` for
   navigates and the new node ids for branches; the existing handler
   already handles both.
2. **Title bar + auto-title generation.** Re-add the inline-editable
   `<input>` in a header component. Title commits go through
   `Omni.Session.set_title/2`; persistence is automatic. Auto-gen
   uses `OmniUI.Title.generate/3` (still in the codebase). The trigger
   moves from `agent_event(:stop, ...)` to `agent_event(:turn,
   {:stop, _}, ...)`. Config key was `config :omni, OmniUI.AgentLive,
   title_generation: ...` — restore.
3. **Artifacts + REPL tools.** Both need `session_id` at construction.
   The session id is in `snapshot.id`, available immediately after
   `start_session/2`. Pass tools as the `:tools` option to
   `start_session/2`. The `tool_use_components` map plumbing already
   works. The `Artifacts.PanelComponent` and toggle button get
   re-mounted in `AgentLive.render/1`.
4. **Doc sync.** Rewrite `context/architecture.md` and
   `context/roadmap.md` to reflect the post-pivot world. The
   architecture doc has whole sections (`Source of Truth`, `Streaming
   Architecture`, `Persistence`, `Sessions`) that are now wrong. The
   roadmap's Persistence and Session Management workstreams need a
   "superseded by the Session pivot" note plus new entries for the
   integration phases.
5. **Test backfill.** `test/omni_ui/macro_test.exs` is `@moduletag
   :wip`. Rewrite for `start_session`/`update_session` and the
   session-event injection. Possibly add an integration test exercising
   `start_session/2` end-to-end with `Req.Test` stubbing the LLM HTTP
   (see omni_agent's test suite for the pattern).
6. **Polish backlog (was already in roadmap, still valid):** error
   retry on errored turns, the `agent_event/3` →
   `session_event/3` rename question, event-name rationalisation, Hex
   docs, package API surface, mobile artifacts panel UX.

---

## Reference: `omni_agent` API surface you'll touch

(Read the actual moduledocs — these summaries are pointers, not specs.)

- `Omni.Session.start_link(opts)` — opts include `:agent` (kw),
  `:store` (`{Module, cfg}` tuple), `:new` / `:load` (mutually
  exclusive; omit for auto), `:subscribe`, `:subscribers`,
  `:idle_shutdown_after`, `:title`. Caller links to the session.
- `Omni.Session.subscribe(pid, opts)` — `mode: :controller |
  :observer`. Returns `{:ok, %Snapshot{}}`. Observers don't keep the
  session alive when idle.
- `Omni.Session.{prompt, cancel, navigate, branch, set_title,
  set_agent}` — operations.
- `Omni.Session.{get_snapshot, get_tree, get_title, get_agent}` —
  inspection.
- Events: `{:session, pid, event, data}` where `event` is one of:
  `:text_start | :text_delta | :text_end | :thinking_start |
  :thinking_delta | :thinking_end | :tool_use_start | :tool_use_delta
  | :tool_use_end | :tool_result | :message | :step | :turn | :pause
  | :retry | :error | :cancelled | :state | :status | :tree | :title
  | :store`. `:turn` payload is `{:stop, %Response{}}` or `{:continue,
  %Response{}}`. `:tree` payload is `%{tree: Tree.t(), new_nodes:
  [node_id()]}`. `:store` payload is `{:saved, :tree | :state}` or
  `{:error, :tree | :state, reason}`.
- `Omni.Session.Tree` — same shape as the deleted `OmniUI.Tree`:
  `%Tree{nodes, path, cursors}`, with `messages/1`, `usage/1`,
  `children/2`, `siblings/2`, `navigate/2`, `extend/1`, `push/3`,
  `push_node/3`, `path_to/2`, `roots/1`, `head/1`, `get_node/2`,
  `get_message/2`. Implements `Enumerable` over the active path.
- `Omni.Session.Snapshot` — `%Snapshot{id, title, tree, agent}`.
  `agent` is `%Omni.Agent.Snapshot{state, pending, partial}`.
- `Omni.Session.Store` — behaviour with `save_tree/4`,
  `save_state/4`, `load/3`, `list/2`, `delete/3`, `exists?/2`.
  Dispatched via `{:adapter, cfg}` tuple.
- `Omni.Session.Store.FileSystem` — reference adapter. Files at
  `<base_path>/<id>/{nodes.jsonl, session.json}`.
- `Omni.Session.Manager` — **survey first; this is your starting
  point.** Living at `../omni_agent/lib/omni/session/manager.ex` and
  the `manager/` subdir.

## Reference: `omni_ui` structure

```
lib/
  omni_ui.ex                       # macro + start_session/update_session/notify
  omni_ui/
    agent_live.ex                  # mountable LiveView (slim now)
    components.ex                  # Layer 1 function components
    editor_component.ex            # textarea + drag-drop file uploads
    handlers.ex                    # event/info/session-event dispatch
    helpers.ex                     # small util functions
    notification.ex                # toaster struct
    sessions_component.ex          # drawer (UNMOUNTED, store calls stubbed)
    title.ex                       # title generation library (no call sites)
    tree_faker.ex                  # test fixture (uses Omni.Session.Tree)
    turn.ex                        # %OmniUI.Turn{} + Turn.all/1, Turn.get/2, Turn.new/3
    turn_component.ex              # rendering one turn (LiveComponent)
    artifacts/                     # tool + panel + plug + repl extension (unwired)
    repl/                          # tool + sandbox (unwired)
priv/static/omni_ui.css            # OKLCH theme + markdown typography
omni_ui_dev/                       # companion Phoenix app for browser testing
test/                              # ExUnit suite
context/
  architecture.md                  # STALE — rewrite at end of follow-ups
  roadmap.md                       # STALE — rewrite at end of follow-ups
  session_pivot.md                 # WHY of the pivot (handover to omni_agent)
  handover.md                      # this doc
```

## Conventions

- **Run commands from the project root**, not `omni_ui_dev/`. Mix
  resolves both. `mix format --check-formatted`, not `mix format`.
- **Don't start the dev server.** The user runs it manually and reports
  back. Compiling, testing, format-checking are fine.
- **Match commit message style** of `git log --oneline`: imperative
  mood, ~50-char subject, terse body. Sign with `AI-assisted commit
  (Claude)`.
- **Component messages from LiveComponents to the parent LiveView**
  use the tuple `{OmniUI, :event_name, ...args}` (e.g. `{OmniUI,
  :new_message, msg}`, `{OmniUI, :edit_message, turn_id, msg}`,
  `{OmniUI, :notify, notification}`). Subscribed-session events use
  `{:session, pid, event, data}`. Don't conflate the two.
- **`omni:` prefix on phx-click events** for events the macro routes
  through `OmniUI.Handlers.handle_event/3`. Bare event names belong to
  the consumer.
- **No emojis in code or commit messages.** No comments unless they
  explain a non-obvious *why*. Read CLAUDE.md.

## Things to watch out for

- The macro injects `handle_info({:session, _, _, _}, …)` *and* the
  consumer's existing `handle_info` clauses fall through via
  `defoverridable`. If you add a new info handler in `AgentLive` that
  pattern-matches loosely, it can swallow session events. Match
  precisely.
- `start_session/2` uses `stream(:turns, turns, reset: true)` and
  `stream(:notifications, [], reset: true)` so it can be called both
  from a fresh mount (where streams are pre-initialised in mount) and
  from `handle_params/3`. Don't drop the `reset: true`.
- `OmniUI.Turn.get(tree, first_id)` is the rebuild path on a `:tree`
  event. It walks forward from `first_id` to the next non-tool-result
  user boundary, so a multi-step turn (continuations, tool calls)
  collapses correctly into one renderable turn. Don't try to use
  `Turn.new/3` from raw messages here — `Turn.get/2` does the right
  thing.
- The `:store {:saved, _}` clause in `OmniUI.Handlers` is what patches
  the URL on first save. If you add a new "fresh session" code path
  (e.g. via Manager) make sure `:url_synced` defaults to `false`
  there too, or the URL won't pin.
- `Application.fetch_env!(:omni, [path, list])` doesn't take nested
  paths — it's `Application.get_env(:omni, OmniUI.AgentLive, []) |>
  Keyword.get(:store)`. The bug bit me; don't repeat it.
- `Omni.Session` links to its caller. If you `start_link` from the LV
  process, the session dies when the LV dies. That's exactly what we
  want for the no-Manager state and is partly *why* Manager is the
  next step (Manager-supervised sessions outlive LV disconnects).
- `agent_event/3` is still the consumer callback name even though
  events come from `{:session, …}` messages. Renaming was deferred. Be
  consistent: the *event tag* is `:session` (in the tuple) but the
  *callback name* is `agent_event`.

---

## How to start

1. Read `context/session_pivot.md` (5 min) for context on why the
   pivot happened.
2. Read `CLAUDE.md` and `context/architecture.md` (10 min). Note that
   architecture.md is stale; you're reading it for the bits that *are*
   still true (component hierarchy, CSS theming, custom tool-use
   components).
3. Read `context/roadmap.md` skimming-style — most of it is wrong
   post-pivot, but it's useful for orientation around polish items.
4. Survey `Omni.Session.Manager` per Phase A above.
5. Present a plan to the user, wait for approval, then implement.

If anything in this doc disagrees with the code, **the code wins** —
flag the discrepancy and update this doc.
