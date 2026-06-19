# Omni.UI Roadmap

Open work on the Omni.UI package. The architectural workstreams
(macro, persistence, advanced tooling, session management, the
`Omni.Session` pivot) are all done — see `context/design.md` for the
current shape. What remains is mostly polish, naming/API decisions,
and a release path.

---

## Polish & Release

Smaller items that don't need major design work but should land
before a public release.

- **`agent_event/3` → `session_event/3` rename** — the callback name
  predates the `:session` event prefix. Renaming would align the
  callback with the event tag it handles, but it's a breaking change
  for any out-of-tree consumer. Decide whether the symmetry is worth
  the churn before the public API locks in.

- **Per-tool timeouts** — the agent has a single timeout applied to
  all tool calls; the REPL tool has its own separate setting. Need to
  decide whether tools can declare their own timeout that overrides
  the agent default. Likely requires changes in `omni_agent`.

- **Event-name rationalisation** — across `phx-click` UI events,
  LiveView `handle_event` events, events scoped to AgentLive vs the
  macro vs LiveComponents, and the symbolic atoms passed to the
  `agent_event/3` callback. Today they've accumulated organically
  (`omni:*` namespaced vs bare `save_title`, component-bubbled
  events, etc.). Review for a coherent, documented convention before
  the public API locks in.

- **Config-key rationalisation** — configuration spans `:omni` and
  `:omni_ui` atoms with a mix of bare-app and module-scoped keys
  (`config :omni_ui, Omni.UI.Sessions, store: ...`,
  `config :omni_ui, Omni.UI.Files, url_prefix: ...`,
  `config :omni, providers: ...`). Single coherent pattern across
  the Omni ecosystem before release. Dovetails with namespacing.

- **Package API surface** — decide what's public vs internal.
  `Omni.UI`, `Omni.UI.ChatUI`, `Omni.UI.CoreUI`, `Omni.UI.Turn`,
  `Omni.UI.Sessions`, `Omni.UI.Notification`, and the
  Files/Tools/Sessions UI modules
  are public. `Omni.UI.Handlers`,
  `Omni.UI.Helpers`, internal structs may not be. `Omni.UI.TreeFaker`
  lives in `test/support/` (not published).

- **Streaming-perf delta debounce** — debounce text deltas (50–100ms
  timer) to reduce re-renders during fast streaming. Optional —
  current performance is acceptable.

- **Cross-browser QA** — thorough testing across browsers. The
  files panel iframe + sandbox token URLs are the most
  sensitive area.

- **Hex docs** — moduledocs are mostly in shape. Need a usage guide
  covering: the three layers; the `init_session` / `attach_session`
  / `ensure_session` lifecycle; wiring `Omni.UI.Sessions`
  into a supervision tree; mounting
  `Files.Plug`; registering custom tool-use components.

- **Test backfill** — current coverage is good for data
  structures, components, and the macro lifecycle. Areas that would
  benefit from more: `Omni.UI.Handlers` session-event paths
  end-to-end (with stubbed `Omni.Session`), `Omni.UI.SessionsComponent`
  manager-event reducers, branch-error notification mappings.
