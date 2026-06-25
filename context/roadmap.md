# Omni.UI Roadmap

Open work on the Omni.UI package. Architecture and QA are complete —
see `context/design.md` for the current shape.

---

## Future

- **Streaming-perf delta debounce** — debounce text deltas (50–100ms
  timer) to reduce re-renders during fast streaming. Optional —
  current performance is acceptable.

---

## Known Issues

- **`update_session/2` silently fails while agent is busy** —
  `Omni.Session.set_agent` flat-out rejects changes when the agent
  is streaming or paused (`{:error, :busy}`). `update_session/2`
  updates socket assigns optimistically, but the agent keeps the old
  values. The `:state` event after the turn completes then reverts
  the assigns — so the user's change is silently lost. Needs an
  upstream change in `omni_agent`: queue `set_state` calls during
  busy state (analogous to the existing `next_prompt` mechanism)
  so they apply when the agent returns to idle.
