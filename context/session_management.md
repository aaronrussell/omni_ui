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

Click the title in the header → inline edit → save on blur/enter → persist to metadata.

Manual-edited titles are **pinned** (a `title_pinned` flag in metadata) so a later regeneration doesn't clobber them. Also covered: once generation fires once and succeeds, the title is no longer `nil`, so the "title is nil" trigger condition won't re-fire regardless of the pinned flag — but the flag is still useful if we ever add an explicit regenerate action.

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
@spec generate([Omni.Message.t()], Model.ref() | :heuristic) ::
        {:ok, String.t()} | {:error, term()}

def generate(messages, :heuristic), do: {:ok, heuristic(messages)}
def generate(messages, model), do: # LLM call
```

Optionally expose `Title.heuristic/1` publicly as a convenience, but the primary entry point is the unified `generate/2`.

**Why one function, not two:**

- Callers don't branch before calling — `start_async(fn -> Title.generate(msgs, strategy) end)` works for all strategies
- `handle_async` only handles one success shape
- Internal dispatch is a single pattern match

### Config location — AgentLive, not `OmniUI.Title`

`OmniUI.Title` stays pure. No `Application.get_env`, no macro-attribute magic. AgentLive resolves strategy and passes it in:

```elixir
@title_strategy :heuristic  # or read from use opts / app config

defp resolve_title_strategy(socket) do
  case @title_strategy do
    false -> nil
    :main -> socket.assigns.model
    other -> other  # :heuristic or a Model.ref tuple
  end
end

def agent_event(:stop, _, socket) do
  socket = persist(socket)

  case needs_title?(socket) && resolve_title_strategy(socket) do
    nil -> socket
    strategy ->
      start_async(socket, :title, fn ->
        Title.generate(messages_for_title(socket), strategy)
      end)
  end
end

def handle_async(:title, {:ok, {:ok, title}}, socket) do
  save_metadata(socket.assigns.session_id, title: title)
  {:noreply, assign(socket, :title, title)}
end
```

The "off" case is handled by the caller branching on `nil`, not by passing `nil` into `Title.generate/2`.

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
   Click header title → inline edit → save. Adds `:title` and `:title_pinned` to metadata. No LLM involved. Unlocks the session browser being usable.

3. **LLM title generation**
   `OmniUI.Title` module with `generate/2` (LLM + heuristic branches). Configurable via `use OmniUI, title: ...`. AgentLive integration via `start_async` in `agent_event(:stop, ...)`.

4. **Session browser**
   - Extend `Store` behaviour with pagination opts
   - Update `Filesystem` adapter
   - Build `session_list/1` function component
   - Build `SessionBrowserComponent` LiveComponent
   - Wire drawer-from-left in AgentLive header
   - Delete-with-confirm flow

Titles (2+3) before browser (4) because the browser is significantly more useful with real titles. Ordering between 2 and 3 doesn't really matter — they're independent — but 2 establishes the metadata schema that 3 writes into.
