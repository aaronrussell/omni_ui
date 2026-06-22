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

- **Streaming-perf delta debounce** — debounce text deltas (50–100ms
  timer) to reduce re-renders during fast streaming. Optional —
  current performance is acceptable.

- **Cross-browser QA** — thorough testing across browsers. The
  files panel iframe + sandbox token URLs are the most
  sensitive area.
