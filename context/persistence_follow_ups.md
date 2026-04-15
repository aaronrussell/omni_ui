# Persistence Follow-ups — Design Notes

All persistence workstream items have landed. Architectural decisions documented in `architecture.md`:

- JSON serialisation + JSONL filesystem adapter — § Persistence
- Metadata-as-map — § Persistence
- Store/macro decoupling + `ui_event/3` — § Persistence, § `use OmniUI` Macro
- Notifications system — § Notifications
- Save error handling (call-site `save/1` helper in AgentLive) — § Error Handling

This file is retained for historical context. Further persistence work (retry policies, async save queue, etc.) will be scoped under new workstreams if/when real failure patterns emerge.

---

## Follow-up considerations (not blocking)

- **Retry policy.** Current behaviour: one-shot try, log + notify on failure, move on. If filesystem failures turn out to be transient in practice (e.g. brief I/O contention), a bounded retry-with-backoff at the `surface_save_error/1` call sites would be straightforward.
- **Async saves.** Saves are synchronous in the LiveView process. For slow adapters (e.g. network-backed stores) this would block the UI. `Task.start` around the save call would decouple latency at the cost of losing the `:error` return.
