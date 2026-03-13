---
name: omni
description: |
  Use when writing Elixir code that uses the `omni` hex package for LLM integration. Omni provides a unified API for text generation, streaming, tool use, structured output, and stateful agents across Anthropic, OpenAI, Google Gemini, OpenRouter, Ollama, and OpenCode. Use this document when writing Elixir code that depends on the `omni` library.
---

# Omni — Elixir LLM Client Skill

## Installation

```elixir
# mix.exs
{:omni, "~> 1.0"}
```

API keys are read from standard environment variables by default:

| Provider | Env var |
|---|---|
| Anthropic | `ANTHROPIC_API_KEY` |
| Google | `GEMINI_API_KEY` |
| OpenAI | `OPENAI_API_KEY` |
| OpenRouter | `OPENROUTER_API_KEY` |
| Ollama Cloud | `OLLAMA_API_KEY` |
| OpenCode | `OPENCODE_API_KEY` |

Anthropic, OpenAI, and Google are loaded by default. Add others:

```elixir
# config/runtime.exs
config :omni, :providers, [:anthropic, :openai, :openrouter]
```

Override API keys per-provider or at the call site:

```elixir
config :omni, Omni.Providers.Anthropic, api_key: {:system, "MY_KEY"}
# or
Omni.generate_text(model, context, api_key: "sk-...")
```

---

## Core Concepts

**Models** are referenced as `{provider_id, model_id}` tuples. You rarely need to work with `%Model{}` structs directly.

```elixir
{:anthropic, "claude-sonnet-4-5-20250514"}
{:openai, "gpt-4o"}
{:google, "gemini-2.0-flash"}
```

**Context** is the conversation input — a string, a list of messages, or a `%Context{}` struct with system prompt, messages, and tools.

**Response** is the generation result — the assistant's message, token usage/costs, stop reason, and optional structured output.

All public functions return `{:ok, result} | {:error, reason}`.

---

## Text Generation

### Simple (blocking)

```elixir
{:ok, response} = Omni.generate_text({:anthropic, "claude-sonnet-4-5-20250514"}, "Hello!")

response.message.content
#=> [%Omni.Content.Text{text: "Hello! How can I help?"}]

response.usage.total_cost
#=> 0.0003
```

### Multi-turn conversation

```elixir
context = Omni.context(
  system: "You are a helpful assistant.",
  messages: [
    Omni.message(role: :user, content: "What is Elixir?"),
    Omni.message(role: :assistant, content: "Elixir is a functional language..."),
    Omni.message(role: :user, content: "How does it handle concurrency?")
  ]
)

{:ok, response} = Omni.generate_text({:anthropic, "claude-sonnet-4-5-20250514"}, context)
```

### Continuing a conversation

```elixir
# After a response, push all messages (including tool loop messages) back:
context = Omni.Context.push(context, response)
context = Omni.Context.push(context, Omni.message("Tell me more"))

{:ok, response} = Omni.generate_text(model, context)
```

### Options

```elixir
Omni.generate_text(model, context,
  max_tokens: 4096,           # max output tokens
  temperature: 0.7,           # sampling temperature
  thinking: :medium,          # extended thinking (:low, :medium, :high, :max, %{budget: n}, false)
  cache: :short,              # prompt caching (:short or :long)
  timeout: 300_000,           # request timeout ms (default 300s)
  max_steps: 5,               # max tool execution rounds (default :infinity)
  tool_timeout: 30_000,       # per-tool execution timeout ms
  raw: true,                  # attach raw Req request/response tuples
  plug: my_plug               # Req test plug for stubbing in tests
)
```

---

## Streaming

`stream_text/3` returns a `StreamingResponse` — a lazy stream of events.

### Stream to UI and get final response

```elixir
{:ok, stream} = Omni.stream_text({:anthropic, "claude-sonnet-4-5-20250514"}, "Tell me a story")

{:ok, response} =
  stream
  |> Omni.StreamingResponse.on(:text_delta, fn %{delta: text} -> IO.write(text) end)
  |> Omni.StreamingResponse.complete()
```

### Just text chunks

```elixir
stream
|> Omni.StreamingResponse.text_stream()
|> Enum.each(&IO.write/1)
```

### Multiple event handlers

```elixir
{:ok, response} =
  stream
  |> Omni.StreamingResponse.on(:text_delta, fn %{delta: d} -> IO.write(d) end)
  |> Omni.StreamingResponse.on(:thinking_delta, fn %{delta: d} -> IO.write(d) end)
  |> Omni.StreamingResponse.on(:done, fn %{stop_reason: r} -> IO.puts("\nStop: #{r}") end)
  |> Omni.StreamingResponse.complete()
```

### Full event control (Enumerable)

```elixir
for {type, data, _partial} <- stream do
  case type do
    :text_delta -> IO.write(data.delta)
    :tool_use_start -> IO.puts("Calling: #{data.name}")
    :done -> IO.puts("\nDone: #{data.stop_reason}")
    _ -> :ok
  end
end
```

### Event types

Content block lifecycle: `*_start` → `*_delta` → `*_end`

| Event | Data |
|---|---|
| `:text_start` | `%{index: 0}` |
| `:text_delta` | `%{index: 0, delta: "Hello"}` |
| `:text_end` | `%{index: 0, content: %Text{}}` |
| `:thinking_start` | `%{index: 0}` |
| `:thinking_delta` | `%{index: 0, delta: "..."}` |
| `:thinking_end` | `%{index: 0, content: %Thinking{}}` |
| `:tool_use_start` | `%{index: 1, id: "call_1", name: "weather"}` |
| `:tool_use_delta` | `%{index: 1, delta: "{\"city\":"}` |
| `:tool_use_end` | `%{index: 1, content: %ToolUse{}}` |
| `:tool_result` | `%ToolResult{}` (between tool loop rounds) |
| `:done` | `%{stop_reason: :stop}` |
| `:error` | error reason term |

### Cancellation

```elixir
Omni.StreamingResponse.cancel(stream)
```

---

## Structured Output

Use `Omni.Schema` to build a JSON Schema map and pass it via the `:output` option. The response is validated and decoded automatically with retries on failure.

```elixir
import Omni.Schema

schema = object(%{
  name: string(description: "The capital city"),
  population: integer(description: "Approximate population")
}, required: [:name, :population])

{:ok, response} = Omni.generate_text(
  {:anthropic, "claude-sonnet-4-5-20250514"},
  "What is the capital of France?",
  output: schema
)

response.output
#=> %{name: "Paris", population: 2161000}
```

### Schema builders

```elixir
import Omni.Schema

string(description: "...", min_length: 1, max_length: 100)
integer(minimum: 0, maximum: 100)
number(description: "...")
boolean()
enum(["red", "green", "blue"])
array(string(), min_items: 1)              # typed array
object(%{key: string()}, required: [:key]) # nested object
any_of([string(), integer()])              # union type

# Compose deeply nested schemas:
object(%{
  users: array(object(%{
    name: string(),
    age: integer(minimum: 0),
    role: enum(["admin", "user"])
  }, required: [:name, :age]))
}, required: [:users])
```

---

## Tools

Tools give the model access to external capabilities. When tools have handlers, Omni automatically executes them and feeds results back until the model produces a final text response.

### Inline tools

```elixir
weather_tool = Omni.tool(
  name: "get_weather",
  description: "Gets the current weather for a city",
  input_schema: Omni.Schema.object(
    %{city: Omni.Schema.string(description: "City name")},
    required: [:city]
  ),
  handler: fn input -> "72°F and sunny in #{input.city}" end
)

context = Omni.context(
  messages: [Omni.message("What's the weather in London?")],
  tools: [weather_tool]
)

{:ok, response} = Omni.generate_text({:anthropic, "claude-sonnet-4-5-20250514"}, context)
```

### Tool modules (reusable)

```elixir
defmodule MyApp.Tools.GetWeather do
  use Omni.Tool, name: "get_weather", description: "Gets the weather for a city"

  def schema do
    import Omni.Schema
    object(%{city: string(description: "City name")}, required: [:city])
  end

  def call(input) do
    WeatherAPI.fetch(input.city)
  end
end
```

**Important**: Import `Omni.Schema` inside `schema/0`, not at the module level. It is not auto-imported by `use Omni.Tool`.

### Stateful tools

When a tool needs runtime state (DB conn, config, API client), implement `init/1` and `call/2`:

```elixir
defmodule MyApp.Tools.DbLookup do
  use Omni.Tool, name: "db_lookup", description: "Looks up a record by ID"

  def schema do
    import Omni.Schema
    object(%{id: integer()}, required: [:id])
  end

  def init(repo), do: repo

  def call(input, repo) do
    repo.get(MyApp.Record, input.id)
  end
end

# Usage — state is bound at construction:
tool = MyApp.Tools.DbLookup.new(MyApp.Repo)
```

### Using tools

```elixir
tools = [MyApp.Tools.GetWeather.new(), MyApp.Tools.DbLookup.new(MyApp.Repo)]

context = Omni.context(
  messages: [Omni.message("What's the weather in Paris?")],
  tools: tools
)

{:ok, response} = Omni.generate_text({:anthropic, "claude-sonnet-4-5-20250514"}, context)
```

### Schema-only tools (no auto-execution)

A tool with `handler: nil` won't be auto-executed. The loop breaks and returns the response with `ToolUse` blocks for manual handling:

```elixir
tool = Omni.tool(
  name: "search",
  description: "Web search",
  input_schema: Omni.Schema.object(%{query: Omni.Schema.string()}, required: [:query])
  # no :handler — schema-only
)
```

---

## Agents

`Omni.Agent` wraps the generation loop in a GenServer for stateful, multi-turn conversations with tool approval gates, pause/resume, and prompt queuing.

### Quick start (no callback module)

```elixir
{:ok, agent} = Omni.Agent.start_link(model: {:anthropic, "claude-sonnet-4-5-20250514"})
:ok = Omni.Agent.prompt(agent, "Hello!")

# Events arrive as process messages
receive do
  {:agent, ^agent, :text_delta, %{delta: text}} -> IO.write(text)
  {:agent, ^agent, :done, response} -> IO.puts("\nDone!")
end
```

### Custom agent with callbacks

```elixir
defmodule MyAgent do
  use Omni.Agent

  @impl Omni.Agent
  def init(opts) do
    {:ok, %{user: opts[:user]}}
  end

  @impl Omni.Agent
  def handle_stop(%{stop_reason: :length}, state) do
    {:continue, "Continue where you left off.", state}
  end

  def handle_stop(_response, state) do
    {:stop, state}
  end
end

{:ok, agent} = MyAgent.start_link(
  model: {:anthropic, "claude-sonnet-4-5-20250514"},
  system: "You are a helpful assistant.",
  user: :current_user
)
```

### Baking defaults into start_link

```elixir
defmodule MyAgent do
  use Omni.Agent

  def start_link(opts \\ []) do
    defaults = [
      model: {:anthropic, "claude-sonnet-4-5-20250514"},
      system: "You are a research assistant.",
      tools: [SearchTool.new(), FetchTool.new()]
    ]
    super(Keyword.merge(defaults, opts))
  end
end
```

### Start options

| Option | Description |
|---|---|
| `:model` (required) | `{provider_id, model_id}` tuple or `%Model{}` |
| `:system` | System prompt string |
| `:tools` | List of `%Tool{}` structs |
| `:listener` | PID to receive events (defaults to first `prompt/3` caller) |
| `:tool_timeout` | Per-tool timeout ms (default `5_000`) |
| `:opts` | Inference options passed to each step (`:temperature`, `:max_tokens`, etc.) |
| `:name`, `:timeout`, etc. | Standard GenServer options |

### Agent events

Events arrive as `{:agent, pid, type, data}` messages:

**Streaming events** (forwarded from each LLM response):

```elixir
{:agent, pid, :text_start,     %{index: 0}}
{:agent, pid, :text_delta,     %{delta: "Hello"}}
{:agent, pid, :text_end,       %{content: %Text{}}}
{:agent, pid, :thinking_start, %{index: 0}}
{:agent, pid, :thinking_delta, %{delta: "..."}}
{:agent, pid, :thinking_end,   %{content: %Thinking{}}}
{:agent, pid, :tool_use_start, %{index: 1, id: "call_1", name: "search"}}
{:agent, pid, :tool_use_delta, %{delta: "{\"q\":"}}
{:agent, pid, :tool_use_end,   %{content: %ToolUse{}}}
```

**Agent lifecycle events**:

```elixir
{:agent, pid, :tool_result, %ToolResult{}}  # tool executed
{:agent, pid, :turn,        %Response{}}    # intermediate turn, agent continuing
{:agent, pid, :done,        %Response{}}    # prompt round complete
{:agent, pid, :pause,       %ToolUse{}}     # waiting for tool approval
{:agent, pid, :retry,       reason}         # non-terminal error, retrying
{:agent, pid, :error,       reason}         # terminal error
{:agent, pid, :cancelled,   nil}            # cancel was invoked
```

### Callbacks

All callbacks are optional with sensible defaults. Available callbacks:

| Callback | Receives | Returns | Default |
|---|---|---|---|
| `init(opts)` | start_link opts | `{:ok, assigns}` or `{:error, reason}` | `{:ok, %{}}` |
| `handle_stop(response, state)` | `%Response{}`, `%State{}` | `{:stop, state}` or `{:continue, content, state}` | `{:stop, state}` |
| `handle_tool_call(tool_use, state)` | `%ToolUse{}`, `%State{}` | `{:execute, state}`, `{:reject, reason, state}`, or `{:pause, state}` | `{:execute, state}` |
| `handle_tool_result(result, state)` | `%ToolResult{}`, `%State{}` | `{:ok, result, state}` | `{:ok, result, state}` |
| `handle_error(error, state)` | error term, `%State{}` | `{:stop, state}` or `{:retry, state}` | `{:stop, state}` |
| `terminate(reason, state)` | shutdown reason, `%State{}` | any | no-op |

The `state` argument is an `%Omni.Agent.State{}` with these fields:

- `state.model` — the `%Model{}`
- `state.context` — the committed `%Context{}` (messages, tools, system)
- `state.opts` — agent-level inference options
- `state.status` — `:idle`, `:running`, or `:paused`
- `state.usage` — cumulative `%Usage{}`
- `state.assigns` — user-defined map (like Phoenix socket assigns)
- `state.step` — current step counter in the active prompt round

### Agent public API

```elixir
Omni.Agent.prompt(agent, "Hello!")              # send a prompt
Omni.Agent.prompt(agent, content, max_steps: 5) # with per-round opts
Omni.Agent.resume(agent, :approve)              # resume after pause
Omni.Agent.resume(agent, {:reject, "Denied"})   # reject paused tool
Omni.Agent.cancel(agent)                        # cancel current round
Omni.Agent.add_tools(agent, [tool])             # add tools (when idle)
Omni.Agent.remove_tools(agent, ["tool_name"])   # remove tools (when idle)
Omni.Agent.clear(agent)                         # clear messages & usage
Omni.Agent.listen(agent, pid)                   # set event listener
Omni.Agent.get_state(agent)                     # full %State{}
Omni.Agent.get_state(agent, :usage)             # single field
```

### Pause and resume (tool approval)

```elixir
defmodule ApprovalAgent do
  use Omni.Agent

  @impl Omni.Agent
  def handle_tool_call(%{name: "dangerous_action"}, state) do
    {:pause, state}  # sends {:agent, pid, :pause, %ToolUse{}} to listener
  end

  def handle_tool_call(_tool_use, state) do
    {:execute, state}
  end
end

# In the listener process:
receive do
  {:agent, agent, :pause, tool_use} ->
    # Inspect tool_use, then:
    Omni.Agent.resume(agent, :approve)
    # or: Omni.Agent.resume(agent, {:reject, "Not allowed"})
end
```

### Prompt queuing (steering)

Calling `prompt/3` while the agent is running stages content for the next turn boundary:

```elixir
:ok = Omni.Agent.prompt(agent, "Stop what you're doing, focus on X instead")
```

The staged prompt overrides `handle_stop`'s decision — the agent continues with the new content.

### Autonomous agent pattern

Use a schema-only tool as a completion signal. The agent loops until the model calls it:

```elixir
task_complete = Omni.tool(
  name: "task_complete",
  description: "Call when the task is fully complete.",
  input_schema: Omni.Schema.object(
    %{result: Omni.Schema.string(description: "Summary of what was accomplished")},
    required: [:result]
  )
)

defmodule ResearchAgent do
  use Omni.Agent

  def start_link(opts \\ []) do
    defaults = [
      model: {:anthropic, "claude-sonnet-4-5-20250514"},
      system: "You are a research assistant. Use your tools to research, " <>
              "then call task_complete with your findings.",
      tools: [SearchTool.new(), FetchTool.new(), task_complete],
      opts: [max_steps: 30]
    ]
    super(Keyword.merge(defaults, opts))
  end

  @impl Omni.Agent
  def handle_stop(%{stop_reason: :tool_use}, state), do: {:stop, state}
  def handle_stop(%{stop_reason: :length}, state) do
    {:continue, "Continue where you left off.", state}
  end
  def handle_stop(%{stop_reason: :stop}, state) do
    {:continue, "Continue working. Call task_complete when finished.", state}
  end
  def handle_stop(_response, state), do: {:stop, state}
end
```

### LiveView integration

Agent events map directly to `handle_info/2`:

```elixir
def handle_event("submit", %{"prompt" => text}, socket) do
  :ok = Omni.Agent.prompt(socket.assigns.agent, text)
  {:noreply, socket}
end

def handle_info({:agent, _pid, :text_delta, %{delta: text}}, socket) do
  {:noreply, stream_insert(socket, :chunks, %{text: text})}
end

def handle_info({:agent, _pid, :done, _response}, socket) do
  {:noreply, assign(socket, :status, :complete)}
end

def handle_info({:agent, _pid, :error, reason}, socket) do
  {:noreply, put_flash(socket, :error, "Agent error: #{inspect(reason)}")}
end
```

---

## Data Types Reference

### Messages and content blocks

Two roles only: `:user` and `:assistant`. No `:tool` role — tool results are content blocks inside user messages.

```elixir
# Create messages
Omni.message("Hello!")                                    # user message from string
Omni.message(role: :user, content: "Hello!")              # explicit role
Omni.message(role: :assistant, content: "Hi there!")      # assistant message
```

Content blocks are separate structs under `Omni.Content`. Pattern match on struct name:

| Struct | Fields | Notes |
|---|---|---|
| `%Text{text, signature}` | text string, optional signature | Most common block |
| `%Thinking{text, signature, redacted_data}` | Chain-of-thought | `text` is nil when redacted |
| `%Attachment{source, media_type, description}` | `{:base64, data}` or `{:url, url}` | Images, PDFs |
| `%ToolUse{id, name, input, signature}` | Model's tool invocation request | In assistant messages |
| `%ToolResult{tool_use_id, name, content, is_error}` | Tool execution output | In user messages |

### Response

```elixir
response.message           #=> %Message{role: :assistant, content: [...]}
response.messages          #=> all messages from generation (includes tool loop rounds)
response.usage             #=> %Usage{input_tokens: 10, output_tokens: 25, total_cost: 0.0003}
response.stop_reason       #=> :stop | :length | :tool_use | :refusal | :error
response.output            #=> decoded map when :output option was set
response.error             #=> error description when stop_reason is :error
response.raw               #=> [{%Req.Request{}, %Req.Response{}}] when :raw was set
```

### Usage

```elixir
response.usage.input_tokens      #=> non_neg_integer
response.usage.output_tokens     #=> non_neg_integer
response.usage.total_tokens      #=> sum of all token fields
response.usage.total_cost        #=> USD cost (computed from model pricing)

# Accumulate across requests:
total = Omni.Usage.add(usage1, usage2)
total = Omni.Usage.sum([usage1, usage2, usage3])
```

### Model

```elixir
{:ok, model} = Omni.get_model(:anthropic, "claude-sonnet-4-5-20250514")
model.id                  #=> "claude-sonnet-4-5-20250514"
model.name                #=> "Claude Sonnet 4.5"
model.context_size        #=> 200000
model.max_output_tokens   #=> 8192
model.reasoning           #=> true/false
model.input_modalities    #=> [:text, :image, :pdf]
model.input_cost          #=> USD per million tokens
model.output_cost         #=> USD per million tokens

{:ok, models} = Omni.list_models(:anthropic)

# Register a custom model:
model = Omni.Model.new(
  id: "my-fine-tune",
  name: "My Fine-Tune",
  provider: Omni.Providers.OpenAI,
  dialect: Omni.Dialects.OpenAICompletions,
  context_size: 128_000,
  max_output_tokens: 16_384,
  input_cost: 2.0,
  output_cost: 8.0
)
Omni.put_model(:openai, model)
```

---

## Built-in Providers and Dialects

| Provider module | ID | Default dialect |
|---|---|---|
| `Omni.Providers.Anthropic` | `:anthropic` | `Omni.Dialects.AnthropicMessages` |
| `Omni.Providers.OpenAI` | `:openai` | `Omni.Dialects.OpenAICompletions` |
| `Omni.Providers.Google` | `:google` | `Omni.Dialects.GoogleGemini` |
| `Omni.Providers.OpenRouter` | `:openrouter` | `Omni.Dialects.OpenAICompletions` |
| `Omni.Providers.Ollama` | `:ollama` | `Omni.Dialects.OllamaChat` |
| `Omni.Providers.OpenCode` | `:open_code` | Multi-dialect (per model) |

---

## Testing

Use `Req.Test` stubs via the `:plug` option — no API keys needed:

```elixir
# In tests, stub HTTP responses with a plug:
Omni.generate_text(model, context, plug: fn conn ->
  # Return a Plug response simulating the provider's SSE stream
end)

# Or use Req.Test.stub/2 for more complex scenarios
```

Integration tests go through the full `Omni.generate_text/3` / `Omni.stream_text/3` API with stubbed HTTP. Use `Omni.get_model/2` for model resolution in tests.

---

## Key Conventions

- The term is "tool use", not "tool call" (aligns with Anthropic's API).
- All public APIs return `{:ok, result} | {:error, reason}` tuples.
- Content blocks are separate structs — pattern match on struct name, not a type field.
- Streaming is the primitive — `generate_text` is built on `stream_text`.
- Attachment sources use tagged tuples: `{:base64, data}` or `{:url, url}`.
- `Omni.Schema` atom keys stay atoms — JSON serialization handles stringification.
- Schema option keywords use snake_case (e.g. `min_length:`), normalized to camelCase for JSON Schema.
- Tool `call/1` handlers receive atom-keyed input when the schema uses atom keys.
