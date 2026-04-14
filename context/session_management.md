# Session Management — Design Notes

Design decisions for the session management UI: new session button, session title (manual + LLM-generated), and session browser. Captured from a brainstorm ahead of implementation.

See `persistence.md` for the underlying store behaviour and `roadmap.md` § 4 for where this sits in the roadmap.

---

## Scope

Three discrete features wired into `AgentLive`'s header:

1. **New session button** — already exists, unwired.
2. **Session title** — currently hardcoded as "Untitled".
3. **Session browser** — button exists, unwired.

Plus one adjacent concern: title generation needs an LLM mechanism.

---

## New session button

**Behaviour:** click → generate fresh `session_id`, reset tree via `update_agent(tree: Tree.new(), tools: create_tools(id))`, `push_patch` to new URL.

**Mid-stream edge case:** cancel and navigate, don't disable.

- `Omni.Agent.cancel/1` exists, so cancelling is cheap.
- Clicking "new session" mid-stream is an explicit user signal to abandon the current response.
- Partial turns only commit to the tree on `:stop`, so the current session's tree stays intact at its last completed turn. Nothing to clean up.

**Sequence:** `Omni.Agent.cancel(agent)` → `update_agent(tree: ...)` → `push_patch`.

**Verify during implementation:** `update_agent(tree: ...)` clears `@current_turn`.

---

## Session title

### Trigger

Generate **after the first assistant response completes**, not on first user message.

- Better titles: the model sees what the conversation became about, not just the opening line.
- Accepts one extra second of "Untitled" as the tradeoff.

**Condition:** trigger whenever `:stop` fires and the session title is `nil`. This means legacy sessions without a title will get one on their next message, based on the whole conversation. No special migration path needed.

### Manual editing

Click the title in the header → inline edit → save on blur or Enter → persist to metadata.

**UI shape:** an always-on `<input>` styled to look like plain text until hover/focus. Uses `field-sizing: content` with a `min-w` so it auto-sizes to content while still showing the "Untitled" placeholder when empty. Wrapped in a form with `phx-submit` so Enter commits; the input also has `phx-blur` so losing focus commits. Both paths fire the same `save_title` handler.

**Save rule:** trim the input. No-op if unchanged from current. If empty (and there was a title), save `title: nil` — explicit clear. Otherwise save the new title. `save_metadata` merges, so clearing the title doesn't touch other metadata. In phase 3, clearing becomes the natural "regenerate" path: title back to nil → next `:stop` triggers LLM generation.

**No `title_pinned` flag.** The trigger for LLM regeneration is simply "title is nil" — any non-nil title is effectively pinned because nothing overwrites it. If we ever add an explicit "regenerate title" action, we'll add the flag then. Until then, it's speculative scaffolding.

**Pre-first-message edits.** A user can type a title before any messages exist. Since `save_metadata` now creates a session on disk independently of the tree, and `load` handles metadata-only sessions by returning an empty tree, this works naturally — the session persists with just a title.

**Rename only happens in the header.** The session browser does not support inline rename — keeps the browser focused on find/open/delete.

### Configuration tiers

Developer picks via `use OmniUI, title: ...`:

| Config | Behaviour |
|--------|-----------|
| unset / `false` | Never title. Header shows "Untitled" (or timestamp in the browser list). |
| `:heuristic` | Truncate first user message to ~50 chars. No LLM call. |
| `:main` | Reuse the currently assigned `@model`. |
| `{provider, model}` | Use that specific model (typical: a cheap/fast model like Haiku). |

### API shape — `OmniUI.Title`

**Library function, not in the macro.** Macro's job is wiring (streaming, assigns, event dispatch); title generation is an action the developer triggers at a known moment. Keeping it as a pure library function:

- Stays testable without app-config fixtures
- Keeps the macro lean
- AgentLive becomes the reference implementation of the integration pattern

**Signature — one unified function:**

```elixir
@spec generate(Model.ref() | :heuristic, [Omni.Message.t()], keyword()) ::
        {:ok, String.t()} | {:error, term()}

def generate(:heuristic, messages, _opts), do: ...
def generate(model, messages, opts), do: # LLM call with opts passthrough
```

Argument order matches `Omni.generate_text/3` — strategy/model first (the "how"), messages second (the "input"), opts last.

`heuristic/1` is also public as a convenience. Opts on the model branch pass through to `Omni.generate_text/3` (useful for test stubbing via `plug:`, or for custom `max_tokens`).

Prompt shape: a system prompt instructing the model to reply with only a 3-6 word title, and a single synthesised user message containing `User: ...\n\nAssistant: ...`. The LLM summarises the conversation rather than participating in it — cheaper, more reliable across providers, and naturally strips thinking/tools/attachments since only text blocks contribute.

**Why one function, not two:**

- Callers don't branch before calling — `start_async(fn -> Title.generate(msgs, strategy) end)` works for all strategies
- `handle_async` only handles one success shape
- Internal dispatch is a single pattern match

### Config location — AgentLive, not `OmniUI.Title`

`OmniUI.Title` stays pure. No `Application.get_env`, no macro-attribute magic. AgentLive resolves the strategy at runtime from app config (matching the existing `:omni` namespace used for the store):

```elixir
config :omni, OmniUI.AgentLive, title_generation: :heuristic
# or: title_generation: :main
# or: title_generation: {:anthropic, "claude-haiku-4-5"}
# omit (or set to nil) to disable — the default
```

AgentLive's flow:

1. After persisting on `:stop`, call `maybe_generate_title(socket)`.
2. If `socket.assigns.title == nil` and config resolves to a non-nil strategy, `start_async(socket, :generate_title, fn -> Title.generate(messages, strategy) end)`.
3. `handle_async(:generate_title, {:ok, {:ok, title}}, socket)` only applies if `title` is still nil (race guard — user may have typed a title manually while generation was in flight). Saves metadata and assigns.
4. `{:error, _}` and `{:exit, _}` paths log at `:info` and silently skip. Next `:stop` retries naturally because title is still nil.

---

## Session browser

### Form factor

**Drawer from the left.**

- History icon is on the left; drawer direction is spatially consistent.
- Modal feels disruptive for a frequently-used UI.
- Matches Claude.ai / ChatGPT mental model.
- Mobile: eventually becomes full-screen takeover (same discussion as the artifacts panel).

### Pagination

**"Load more" button, 50 per page default.**

- Infinite scroll is nicer UX but adds IntersectionObserver hooks and LiveView complexity.
- Normal pagination feels dated for a history list.
- Load more is dead simple and can be upgraded to infinite scroll later without API changes.

`Store.list/1` opts get extended with `:limit` / `:offset` (or `:cursor`) as part of this work. Filesystem adapter implements accordingly.

### Component shape — both layers

Mirrors the existing Layer 1 / Layer 2 split (`turn/1` function component + `TurnComponent` LiveComponent):

- **`OmniUI.Components.session_list/1`** — function component. Takes a `sessions` assign + slots for row actions. Pure rendering.
- **`OmniUI.SessionBrowserComponent`** — LiveComponent wrapping the function component. Owns list state, load-more, open/delete events. Can be embedded or router-mounted.

AgentLive uses the LiveComponent. Developers with `use OmniUI` can pick whichever fits their use case.

### Session management

- **Delete** — in the browser (trash icon per row + confirm). Browsers are where you manage.
- **Rename** — header only (see above).
- **Current session** highlighted in the list. Clicking it is a no-op (or closes the drawer).

### Opening a session

Click row → `push_patch` with `session_id` → existing `handle_params` loads it. Drawer closes.

---

## Phasing

Four discrete workstreams, in order:

1. **New session button**
   Wire phx-click, cancel in-flight agent, reset tree, push_patch. Smallest piece, no dependencies.

2. **Manual title editing + storage**
   Click header title → inline edit → save. Adds `:title` to metadata. No LLM involved. Unlocks the session browser being usable.
   Also bundles two Store contract fixes required for sane semantics: `save_metadata` merges rather than overwrites, and `load` handles metadata-only or tree-only sessions (returning empty defaults for the missing piece).

3. **LLM title generation**
   `OmniUI.Title` module with `generate/3` (LLM + heuristic branches). Configurable via `config :omni, OmniUI.AgentLive, title_generation: ...`. AgentLive integration via `start_async` in `agent_event(:stop, ...)`, with `handle_async` race-guarding against concurrent manual edits.

4. **Session browser** (done)
   - `Store.list/1` accepts `:limit`/`:offset`; callers infer `has_more` from list length
   - Macro injects `__omni_store__/0` alongside the other store helpers so collaborators (like the sessions drawer) can receive the store module as an assign
   - `OmniUI.Components.session_list/1` — pure function component: one row per session, current session highlighted, `:actions` slot for per-row controls
   - `OmniUI.SessionsComponent` — LiveComponent: overlay drawer (plain divs with backdrop + ESC close), fetches first page on mount, "Load more" appends, inline two-step delete confirm
   - AgentLive: `view_sessions` assign mirrors `view_artifacts`; handles `open_sessions`/`close_sessions`/`switch_session` events; `handle_info({OmniUI, :active_session_deleted}, ...)` push_patches to `/` when the active session is deleted

Titles (2+3) before browser (4) because the browser is significantly more useful with real titles. Ordering between 2 and 3 doesn't really matter — they're independent — but 2 establishes the metadata schema that 3 writes into.
