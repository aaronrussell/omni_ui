# Omni UI Vision

A LiveView component kit for building agent chat interfaces, powered by Omni. Lightweight, hackable, and composable — designed to demo Omni and give developers building blocks for their own agent UIs.

---

## 1. Component Inventory

The component inventory, data structures, and naming are documented in `architecture.md`. This section captures the intent behind each component.

### AgentLive

The mountable LiveView — the "just give me an agent" entry point. Composes `chat_interface/1` alongside an artifacts panel into a complete, ready-to-use agent interface. Mount it directly or embed via `live_render/3`.

```elixir
# Direct route
live "/agent", OmniUI.AgentLive

# Embedded in another LiveView
live_render(@socket, OmniUI.AgentLive,
  id: "agent",
  session: %{"provider" => :anthropic, "model" => "claude-sonnet-4-20250514"}
)
```

A dev who doesn't need artifacts or the outer shell can skip this entirely and build their own LiveView using `chat_interface/1` and the function components directly.

### chat_interface/1

The inner core — a function component composing the turn stream, current turn, editor, and usage into a chat UI. The developer controls this layout in their own LiveView (via `use OmniUI`), or gets it pre-composed inside `AgentLive`.

The developer is free to skip `chat_interface/1` entirely and compose the individual function components however they like.

### Content Block Renderers

Function components, one per block type. Stateless. Pattern-matched on Omni content struct type. These are the leaves of the tree.

- **text** — renders markdown text content.
- **thinking** — renders model thinking/reasoning. Collapsible.
- **tool_use** — renders a tool call paired with its result. Shows the tool name, input params, and the result content. When no result is available yet (streaming), shows a pending/spinner state.
- **attachment** (TODO) — renders a file or image attachment. Used in user messages and potentially tool results.

### MessageEditor

LiveComponent. Owns composition state — textarea input, in-progress attachments. Builds up a message internally and sends the completed message to the parent on submit. LiveComponent is justified here because high-frequency keystroke and attachment state should be isolated from the parent.

---

## 2. Integration Surface

Three layers — developers pick their entry point based on how much control they want.

### Layer 1: Function Components

The actual UI pieces — `turn/1`, `user_message/1`, `assistant_message/1`, `content_block/1`, `chat_interface/1`, etc. Pure rendering, zero state (except `MessageEditor` LiveComponent). These are the building blocks of the kit.

Developers can use any component individually, restyle them, skip ones they don't need, or replace them with their own. This is the "hackable kit" layer. All function components live in `OmniUI.Components`.

### Layer 2: `use OmniUI` Macro

Adds agent capabilities to any LiveView. Injects:

- `handle_info` clauses for streaming events from the Agent process
- State management (accumulating deltas into `@current_turn`, pushing completed turns to `@streams.turns`)
- `OmniUI.init/2` helper to set up assigns and start the Agent

The developer owns their template entirely. They compose function components from Layer 1 however they like, interleaved with their own markup.

```elixir
defmodule MyAppWeb.ChatLive do
  use MyAppWeb, :live_view
  use OmniUI

  def mount(_params, _session, socket) do
    {:ok, OmniUI.init(socket, provider: :anthropic, model: "claude-sonnet-4-20250514")}
  end

  def render(assigns) do
    ~H"""
    <.my_logo />
    <OmniUI.Components.chat_interface
      turns={@streams.turns}
      current_turn={@current_turn}
      usage={@usage} />
    """
  end
end
```

### Layer 3: `OmniUI.AgentLive`

The mountable LiveView — composes Layers 1 and 2 into a ready-to-use agent interface with artifacts panel. For the "just give me an agent" use case — demos, prototyping, or embedding via `live_render/3`.

`AgentLive` is a reference implementation, not a separate thing. It's built with the same primitives a developer would use.

### Streaming

See `architecture.md` for the full streaming architecture. In summary: the Agent GenServer sends `{:agent, pid, type, data}` messages to the LiveView via `handle_info`. The LiveView accumulates deltas into `@current_turn`. On completion, the turn is pushed to the stream. Streaming state is determined by `@current_turn != nil`.

### Persistence

Pluggable via behaviours. The UI kit doesn't dictate how things are stored — developers implement modules that handle save/load. A basic filesystem implementation ships with the package for development and simple use cases.

The exact API is TBD, but we know persistence will need to cover at least:

- **Conversations** — save/load message history, support multiple sessions. The core use case.
- **Settings** — user preferences like model choice, thinking mode, temperature. May be per-session or global.
- **Assets** — unclear. If tools produce files, sandboxed code output, or artifacts, where do those go? Might be part of the Store behaviour, might be a separate concern handled by the tools themselves.

This is an area with significant unknowns. `Omni.Agent` likely needs new callbacks for persistence hooks. The boundaries between what the Store handles vs what tools handle vs what the Agent manages will emerge as we build. The commitment is to the *pattern* (pluggable behaviours, ship a default FS adapter), not the specific API shape.

### Package Boundary

Separate hex package (`omni_ui` or similar). Depends on `omni` but the core library stays UI-free.

**Dev workflow:** Build initially as a standalone Phoenix app for fast prototyping. Once the component shapes stabilise, extract the modules into a package with a dev Phoenix app in a subdirectory for continued development and demos.

### Decisions

1. **Three-layer architecture.** Function components (hackable) → `use OmniUI` macro (wiring) → `AgentLive` (mountable). Developers pick their level.
2. **Function components by default.** State flows down via assigns. `MessageEditor` is the exception — a LiveComponent justified by state isolation. See `architecture.md` for component structure.
3. **`use OmniUI` handles streaming plumbing.** Injects `handle_info`, state management, and init into the developer's own LiveView.
4. **Naming: `AgentLive` is the outer shell, `chat_interface/1` is the inner core.** AgentLive wraps chat_interface with artifacts and layout chrome. chat_interface composes the turn stream, editor, and usage display.
5. **Turns, not flat messages.** See `architecture.md` for the data structure rationale and `OmniUI.Turn` struct shape.
6. **Persistence is a behaviour.** Pluggable, ships with a basic FS adapter.
7. **Separate package.** Prototype in Phoenix app first, extract later.

### Deferred (figure out by building)

- Callback hooks and extension points
- Specific persistence API shape (what exactly gets saved/loaded)
- Error handling patterns
- `Omni.Agent` API gaps (state access, streaming callbacks, lifecycle hooks)
- Artifacts
- Message editing / conversation branching

---

## 3. Scope & Phases

### Phase 1: Agent Chat UI (hand-wired)

The core loop. Send a message, stream a response, render the conversation. Built by hand — no macro, no abstractions. The goal is to figure out what the optimal wiring actually is.

- `AgentLive` with manually implemented `handle_info` for Agent streaming events
- Function components in `OmniUI.Components`: `chat_interface`, `turn`, `user_message`, `assistant_message`, `content_block`
- `MessageEditor` LiveComponent for input composition
- `OmniUI.Turn` struct as the rendering-optimized data unit
- All state management done explicitly in the LiveView

**Delivers:** a working chat UI that streams responses. Proves the component architecture and — crucially — reveals what the streaming wiring, state management, and Agent interaction patterns actually look like in practice.

### Phase 2: Extract `use OmniUI` Macro

Now that we know what the wiring looks like, extract it.

- `use OmniUI` macro — extracted from the working Phase 1 code
- `OmniUI.init/2` helper
- `OmniUI.AgentLive` — the Phase 1 LiveView refactored to use the macro (becomes the reference implementation, mountable out of the box)

**Delivers:** the three-layer architecture. The macro is an extraction from real code, not a speculative design.

### Phase 3: Settings & Persistence

Make it usable across sessions. Configure the agent without touching code.

- Settings UI (model selection, thinking mode, temperature, etc.)
- Store behaviour + filesystem adapter
- Save/load conversations, support multiple sessions
- Save/load settings (per-session or global — TBD)

**Delivers:** a chat you can come back to. Surfaces the persistence API shape and any `Omni.Agent` gaps around state access and lifecycle hooks.

### Phase 4: Tool Calling

Where it gets interesting. Agent uses tools, results render inline.

- ToolUseBlock component — renders tool call + result paired together
- Yolo mode by default (auto-execute tools)
- Pending/spinner state for in-flight tool calls
- Pluggable tool renderers (developers can customise how specific tools display)

**Delivers:** a genuine agent UI. This is the demo moment — nothing like it exists in the Elixir ecosystem. Phases 1-4 together are releasable.

### Phase 5: Advanced Tools & Artifacts

The exploratory phase. Code execution, artifacts, richer tool UI.

- Code sandbox — executing Elixir (or other?) code from agent tool calls
- Artifacts panel — rendering tool output as interactive content (HTML, components?)
- How this maps to Elixir's runtime vs the JS sandbox model is unclear
- New UI components for artifact rendering

**Delivers:** TBD. This phase is deliberately fuzzy. We'll have much better intuition for what's possible and useful after shipping phases 1-4.

---

## Phase 1 Learnings

### Turns, not flat messages

The LiveView does **not** mirror the agent's internal message list. The agent manages its own context for generation; the LiveView maintains a stream of `OmniUI.Turn` structs optimised for rendering.

The key insight: a single agent prompt round may involve multiple internal messages (tool calls, tool results, continuation), but in the UI this collapses into **one turn** — a user message paired with an accumulated assistant response. See `architecture.md` for the full `OmniUI.Turn` struct and rationale.

### Tool result pairing — in the turn, not at render time

The original plan was a `tool_result_map/2` helper that joined tool_use blocks with results across messages at render time. Instead, tool results are accumulated into the turn's `tool_results` map as they arrive. No render-time join needed — the turn is self-contained.

---

## Open Questions

- **Artifacts** — What are they? Sandboxed HTML/JS output? LiveView components rendered from agent output? Needs its own exploration.
- **Agent API gaps** — What does `Omni.Agent` need to expose for this UI to work? Streaming callbacks, state persistence, conversation history, token usage. This is a key output of building the UI.
- **Persistence shape** — How does save/load interact with the turn-based data model? Serialising `OmniUI.Turn` vs reconstructing from `Omni.MessageTree`.
