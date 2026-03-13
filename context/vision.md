# Omni UI Vision

A LiveView component kit for building agent chat interfaces, powered by Omni. Lightweight, hackable, and composable — designed to demo Omni and give developers building blocks for their own agent UIs.

---

## 1. Component Inventory

### ChatLive

The mountable LiveView — the "just give me a chat" option. Composes AgentInterface alongside an artifacts panel into a complete, ready-to-use chat interface. Mount it directly or embed via `live_render/3`.

```elixir
# Direct route
live "/chat", OmniUI.ChatLive

# Embedded in another LiveView
live_render(@socket, OmniUI.ChatLive,
  id: "chat",
  session: %{"provider" => :anthropic, "model" => "claude-sonnet-4-20250514"}
)
```

A dev who doesn't need artifacts or the outer shell can skip this entirely and build their own LiveView using AgentInterface and the function components directly.

### AgentInterface (composition, not a component)

The inner core — the composition of components that makes a chat UI. Handles the message list, streaming, agent communication. The developer controls this layout in their own LiveView (via `use OmniUI`), or gets it pre-composed inside `ChatLive`.

Typical composition:

```heex
<OmniUI.message_list messages={@messages} />
<OmniUI.streaming_message :if={@streaming} message={@current_message} />
<OmniUI.message_editor />
<OmniUI.usage_stats usage={@usage} />
```

The developer is free to rearrange, wrap, interleave their own markup, or skip components entirely. `AgentInterface` works standalone — `ChatLive` wraps it with artifacts and layout chrome.

### MessageList

Dumb list. Receives messages as assigns, renders them. Only re-renders when a new message is appended. Each message is a list of content blocks — the component iterates blocks and dispatches to the appropriate renderer.

```heex
<div :for={message <- @messages}>
  <.message message={message} tool_results={tool_result_map(message, @messages)} />
</div>
```

A helper function builds a lookup map of `tool_use_id => result` for each message. For user messages or assistant messages without tool_use blocks, this returns an empty map. Keeps the Message component clean — it just passes the relevant result into each ToolUseBlock.

### Message

Renders a single message (user or assistant). Iterates over content blocks and dispatches to block-type renderers. The role determines wrapper styling, but the rendering logic is the same: walk the blocks.

```heex
<div class={["message", @message.role]}>
  <.content_block :for={block <- @message.content} block={block} />
</div>
```

### Content Block Renderers

Function components, one per block type. Stateless. These are the leaves of the tree.

- **TextBlock** — renders markdown text content.
- **ThinkingBlock** — renders model thinking/reasoning. Collapsible.
- **ToolUseBlock** — renders a tool call paired with its result. Shows the tool name, input params, and the result content. When no result is available yet (streaming), shows a pending/spinner state.
- **AttachmentTile** — renders a file or image attachment. Used in both user messages (input attachments) and potentially tool results.

```heex
<div :if={@block.type == :text}><.text_block block={@block} /></div>
<div :if={@block.type == :thinking}><.thinking_block block={@block} /></div>
<div :if={@block.type == :tool_use}><.tool_use_block block={@block} result={@result} /></div>
```

The tool_use renderer receives the tool_result alongside the tool_use block. The parent component is responsible for pairing them up (matching on tool_use_id), even though they live in different messages structurally.

### StreamingMessage

Visible only while the agent is actively generating. Renders the in-progress assistant message as tokens arrive. Distinct from the static MessageList because:

- It re-renders on every streamed token/event
- It displays tool calls in-progress (no results yet)
- It hosts the stop button and streaming indicators
- When streaming completes, the finished message is pushed to MessageList and this component disappears

A function component. It receives the in-progress message and streaming flag as assigns from the parent LiveView (or AgentInterface composition), which handles all streaming events via `handle_info`.

```heex
<div class="streaming">
  <.message message={@current_message} streaming={true} />
  <.stop_button phx-click="stop_generation" />
</div>
```

### MessageEditor

The input area. A form with a textarea, attachment management, and action buttons. Handles file drops for multimodal input. Possibly includes model selection.

```heex
<form phx-submit="send_message" phx-change="validate">
  <.attachment_list :if={@attachments != []} attachments={@attachments} />
  <textarea phx-drop="attach_file" />
  <div class="actions">
    <.model_selector :if={@show_model_selector} models={@models} selected={@model} />
    <button type="submit">Send</button>
  </div>
</form>
```

### UsageStats

Displays token counts, cost estimate, model info. Dev-facing utility — the kind of thing you'd show in a debug/dev mode or a power-user interface.

---

## 2. Integration Surface

Three layers — developers pick their entry point based on how much control they want.

### Layer 1: Function Components

The actual UI pieces — `message_list`, `message`, `text_block`, `tool_use_block`, `message_editor`, `streaming_message`, `usage_stats`, etc. Pure rendering, zero state. These are the building blocks of the kit.

Developers can use any component individually, restyle them, skip ones they don't need, or replace them with their own. This is the "hackable kit" layer.

### Layer 2: `use OmniUI` Macro

Adds agent capabilities to any LiveView. Injects:

- `handle_info` clauses for streaming events from the Agent process
- State management (accumulating tokens into `@current_message`, flipping `@streaming`, appending completed messages to `@messages`)
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
    <OmniUI.message_list messages={@messages} />
    <OmniUI.streaming_message :if={@streaming} message={@current_message} />
    <div class="my-custom-footer">
      <OmniUI.message_editor />
      <OmniUI.usage_stats usage={@usage} />
    </div>
    """
  end
end
```

### Layer 3: `OmniUI.ChatLive`

The mountable LiveView — composes Layers 1 and 2 into a ready-to-use chat interface with artifacts panel. For the "just give me a chat" use case — demos, prototyping, or embedding via `live_render/3`.

```elixir
# Direct route
live "/chat", OmniUI.ChatLive

# Embedded in another LiveView
live_render(@socket, OmniUI.ChatLive,
  id: "chat",
  session: %{"provider" => :anthropic, "model" => "claude-sonnet-4-20250514"}
)
```

`ChatLive` is a reference implementation, not a separate thing. It's built with the same primitives a developer would use.

### Streaming

The Agent GenServer sends messages to the LiveView process (whether that's the developer's own LiveView via `use OmniUI`, or `ChatLive`) directly via `handle_info`. The macro handles accumulating streaming deltas into `@current_message`, flipping `@streaming` on/off, and appending completed messages to `@messages`. Child components are all function components that re-render from assigns.

```
Agent process --send--> LiveView (with `use OmniUI`)
                           |
                           +--> handle_info (injected by macro)
                           +--> updates assigns
                           +--> re-renders function components
```

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

1. **Three-layer architecture.** Function components (hackable) → `use OmniUI` macro (wiring) → `ChatLive` (mountable). Developers pick their level.
2. **All UI components are function components.** State flows down via assigns. No LiveComponents in the rendering tree.
3. **`use OmniUI` handles streaming plumbing.** Injects `handle_info`, state management, and init into the developer's own LiveView.
4. **`ChatLive` is the outer shell and the default LiveView.** No separate wrapper — `ChatLive` composes AgentInterface + artifacts and is directly mountable. Developers who want full control build their own LiveView instead.
5. **Naming: AgentInterface is the inner core, ChatLive is the outer shell.** AgentInterface handles messages, streaming, and agent comms. ChatLive wraps it with artifacts and layout chrome.
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

The core loop. Send a message, stream a response, render the conversation. Built by hand in a standalone Phoenix app — no macro, no abstractions. The goal is to figure out what the optimal wiring actually is.

- A LiveView with manually implemented `handle_info` for Agent streaming events
- Function components: `message_list`, `message`, `text_block`, `thinking_block`, `streaming_message`, `message_editor`
- All state management done explicitly in the LiveView
- Built in a standalone Phoenix app for prototyping

**Delivers:** a working chat UI that streams responses. Proves the component architecture and — crucially — reveals what the streaming wiring, state management, and Agent interaction patterns actually look like in practice.

### Phase 2: Extract `use OmniUI` Macro

Now that we know what the wiring looks like, extract it.

- `use OmniUI` macro — extracted from the working Phase 1 code
- `OmniUI.init/2` helper
- `OmniUI.ChatLive` — the Phase 1 LiveView refactored to use the macro (becomes the reference implementation, mountable out of the box)

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

## Open Questions

- ~~**Tool result pairing**~~ — Resolved. A `tool_result_map/2` helper builds a lookup of `tool_use_id => result` at render time. Passed into each Message component. MessageList stays dumb, Message stays dumb, the helper does the join.
- **Error rendering** — Rate limits, network failures, context overflow. Inline system message? Toast? Needs a pattern.
- **Message editing / retry** — Not MVP, but the data model should support branching (edit a user message, regenerate from that point). Worth keeping in mind for message IDs.
- **Artifacts** — What are they? Sandboxed HTML/JS output? LiveView components rendered from agent output? Needs its own exploration.
- **Agent API gaps** — What does `Omni.Agent` need to expose for this UI to work? Streaming callbacks, state persistence, conversation history, token usage. This is a key output of building the UI.
