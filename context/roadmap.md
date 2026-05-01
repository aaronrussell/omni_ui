# OmniUI Roadmap

Open work on the OmniUI package. The architectural workstreams
(macro, persistence, advanced tooling, session management, the
`Omni.Session` pivot) are all done — see `context/design.md` for the
current shape. What remains is mostly polish, naming/API decisions,
and a release path.

---

## Polish & Release

Smaller items that don't need major design work but should land
before a public release.

- **Error retry** — errored turns preserve the user message via
  `stream_insert(... status: :error)`. Add a retry button that
  re-prompts the agent. Straightforward given the current tree/turn
  architecture.

- **Streaming-perf delta debounce** — debounce text deltas (50–100ms
  timer) to reduce re-renders during fast streaming. Optional —
  current performance is acceptable.

- **Per-tool timeouts** — the agent has a single timeout applied to
  all tool calls; the REPL tool has its own separate setting. Need to
  decide whether tools can declare their own timeout that overrides
  the agent default. Likely requires changes in `omni_agent`.

- **REPL packaging boundary** — the REPL sandbox/tool/extension
  modules have no UI dependency; they could live in `omni_agent` or
  a separate package. Artifacts is different (it needs the panel
  UI). Conversation needed about where the boundary should sit.

- **`agent_event/3` → `session_event/3` rename** — the callback name
  predates the `:session` event prefix. Renaming would align the
  callback with the event tag it handles, but it's a breaking change
  for any out-of-tree consumer. Decide whether the symmetry is worth
  the churn before the public API locks in.

- **Project namespacing** — `OmniUI` vs `Omni.UI`. The rest of the
  ecosystem uses the `Omni` namespace (`Omni.Agent`, `Omni.Session`).
  Decide whether to align before publishing.

- **Event-name rationalisation** — across `phx-click` UI events,
  LiveView `handle_event` events, events scoped to AgentLive vs the
  macro vs LiveComponents, and the symbolic atoms passed to the
  `agent_event/3` callback. Today they've accumulated organically
  (`omni:*` namespaced vs bare `save_title`, component-bubbled
  events, etc.). Review for a coherent, documented convention before
  the public API locks in.

- **Config-key rationalisation** — configuration spans `:omni` and
  `:omni_ui` atoms with a mix of bare-app and module-scoped keys
  (`config :omni_ui, OmniUI.Sessions, store: ...`,
  `config :omni_ui, OmniUI.Artifacts, base_path: ...`,
  `config :omni_ui, OmniUI.TitleService, model: ...`,
  `config :omni, providers: ...`). Single coherent pattern across
  the Omni ecosystem before release. Dovetails with namespacing.

- **Header bar in `Components`** — the inline-editable title input,
  sessions toggle, and artifacts toggle currently live as a private
  function component inside `AgentLive`. Move into
  `OmniUI.Components` so consumers building their own LiveView can
  reuse it. Stabilise the API first (slot shapes, what state it
  takes vs reads from assigns).

- **Package API surface** — decide what's public vs internal.
  `OmniUI`, `OmniUI.Components`, `OmniUI.Turn`, `OmniUI.Sessions`,
  `OmniUI.TitleService`, `OmniUI.Title`, `OmniUI.Notification`, and
  the Artifacts/REPL modules are public. `OmniUI.Handlers`,
  `OmniUI.Helpers`, `OmniUI.TreeFaker`, internal structs may not be.

- **Hex docs** — moduledocs are mostly in shape. Need a usage guide
  covering: the three layers; the `init_session` / `attach_session`
  / `ensure_session` lifecycle; wiring `OmniUI.Sessions` and
  `OmniUI.TitleService` into a supervision tree; mounting
  `Artifacts.Plug`; registering custom tool-use components.

- **Mobile artifacts panel** — the panel won't work well on mobile
  (the layout assumes a 50%-width right sidebar). Decide responsive
  approach: full-screen takeover, separate route, hidden on mobile.

- **Cross-browser QA** — thorough testing across browsers. The
  artifacts panel iframe + sandbox token URLs are the most
  sensitive area.

- **Test backfill** — current coverage is good for data
  structures, components, and the macro lifecycle. Areas that would
  benefit from more: `OmniUI.Handlers` session-event paths
  end-to-end (with stubbed `Omni.Session`), `OmniUI.SessionsComponent`
  manager-event reducers, branch-error notification mappings.

---

## Unresolved Issues

- **REPL distribution boot** — `OmniUI.REPL.Sandbox.ensure_distributed!/0`
  must run eagerly at app boot, before `Phoenix.Endpoint` starts,
  otherwise the first REPL invocation flips the VM into distributed
  mode mid-request and any PIDs already encoded into Phoenix tokens
  (notably LongPoll session_refs) become "remote" and crash
  `is_process_alive/1`. The dev app calls it from `application.ex`
  as a workaround. Revisit whether a `Sandbox.Boot` child spec or
  supervision-tree entry would be a more discoverable / less-bypassable
  shape for downstream consumers.
