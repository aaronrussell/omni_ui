# Persistence Follow-ups — Design Notes

Working notes for the remaining persistence workstream. Architectural decisions that have landed — JSON serialisation, JSONL filesystem adapter, metadata-as-map, store/macro decoupling, `ui_event/3` callback, notifications system — are documented in `architecture.md` (§ Persistence, § `use OmniUI` Macro, § Notifications). What's left is error handling in saves.

---

## 1. Error handling in saves

Rolls in on top of notifications.

Current state: `save_tree` and `save_metadata` are called synchronously in `agent_event(:stop, ...)`, `ui_event(:model_changed/:thinking_changed, ...)`, and the title blur handler. Pattern-matched on `:ok` — a filesystem failure would raise and crash the LiveView process.

Possibilities:

- Wrap in try/rescue; log on failure; surface via notifications.
- Retry with backoff before giving up.
- Move saves to async tasks so they don't block the UI thread.
- Persistence queue — buffer saves in a GenServer, flush in order, handle retries.

v1 probably just needs the try/rescue + notify path. The queue/async stuff is overengineering until we see real failure patterns.

Open question: does error handling live inside `OmniUI.Store` (so every caller gets it for free) or at the call site (so each consumer decides)? Design-conversation consensus has been **call site** — keeps `OmniUI.Store` decoupled from the notifications system and lets each consumer decide what's user-facing vs silently logged. Concretely: Store calls return `{:ok, _} | {:error, reason}`; AgentLive's `agent_event(:stop, ...)`, `ui_event/3`, and `save_title` wrap them with `with`/`case` and call `OmniUI.notify(:error, ...)` on failure.

---

## Open questions worth surfacing at the start of the next session

1. **Save-error UX** — silent-log vs always-notify vs notify-after-N-failures? And is retry in scope for v1 or a separate workstream?
