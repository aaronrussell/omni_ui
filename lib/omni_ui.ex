defmodule OmniUI do
  @moduledoc """
  OmniUI adds agent chat capabilities to any LiveView.

  ## Usage

      defmodule MyAppWeb.ChatLive do
        use Phoenix.LiveView
        use OmniUI

        def render(assigns) do
          ~H\"\"\"
          <.chat_interface>
            ...
          </.chat_interface>
          \"\"\"
        end

        def mount(_params, _session, socket) do
          {:ok, start_agent(socket, model: {:anthropic, "claude-sonnet-4-20250514"})}
        end

        # Optional: observe agent events after default handling
        @impl OmniUI
        def agent_event(:stop, response, socket) do
          MyApp.Analytics.track(response.usage)
          socket
        end

        def agent_event(_event, _data, socket), do: socket
      end

  The macro:

  - Imports `OmniUI.Components` and `start_agent/2` / `update_agent/2`
  - Injects `handle_event/3` clauses for OmniUI-namespaced events
  - Injects `handle_info/2` clauses for agent streaming and component messages
  - Wraps developer-defined handlers via `defoverridable` so OmniUI events
    are dispatched first and unrecognised events fall through
  - Injects default `agent_event/3` and `ui_event/3` pass-throughs if the
    developer doesn't define them

  Persistence is a separate subsystem (`OmniUI.Store`) — the macro has no
  knowledge of it. Consumers call `OmniUI.Store.save_tree/3` and friends
  directly, and use the `ui_event/3` callback to observe macro-handled
  events worth persisting.
  """

  import Phoenix.Component
  import Phoenix.LiveView, only: [stream: 3, stream: 4]
  import Omni.Util, only: [maybe_put: 3]

  # ── Behaviour ─────────────────────────────────────────────────────

  @doc """
  Called after OmniUI's default handling for `:done` and `:error` agent events.

  Receives the event type, event data, and the already-updated socket.
  Must return the socket (possibly with additional assign mutations).
  """
  @callback agent_event(event :: atom(), data :: term(), Phoenix.LiveView.Socket.t()) ::
              Phoenix.LiveView.Socket.t()

  @doc """
  Called after OmniUI handles a UI event that mutates agent-related state.

  Fires for:

    * `:model_changed` — `data` is the resolved `%Omni.Model{}`
    * `:thinking_changed` — `data` is the new thinking level (`false | :low | :medium | :high | :max`)
    * `:navigated` — `data` is the target `node_id`
    * `:message_sent` — `data` is `{node_id, %Omni.Message{}}` for the new user node
    * `:message_edited` — `data` is `{node_id, %Omni.Message{}}` for the new branch node

  Use it to observe macro-handled state changes — for example, to persist
  model/thinking changes via `OmniUI.Store.save_metadata/3`. The macro
  handles agent-state events; consumer-owned events (title editing,
  session management, custom UI) go through standard `handle_event/3`
  and never reach this callback.
  """
  @callback ui_event(event :: atom(), data :: term(), Phoenix.LiveView.Socket.t()) ::
              Phoenix.LiveView.Socket.t()

  # ── Macro ──────────────────────────────────────────────────────────

  defmacro __using__(_opts) do
    quote do
      @behaviour OmniUI
      @before_compile OmniUI
      import OmniUI.Components
      import OmniUI, only: [start_agent: 2, update_agent: 2]
    end
  end

  defmacro __before_compile__(env) do
    has_handle_event = Module.defines?(env.module, {:handle_event, 3})
    has_handle_info = Module.defines?(env.module, {:handle_info, 2})
    has_agent_event = Module.defines?(env.module, {:agent_event, 3})
    has_ui_event = Module.defines?(env.module, {:ui_event, 3})

    event_clauses = inject_handle_event(has_handle_event)
    info_clauses = inject_handle_info(has_handle_info)
    agent_event_clause = unless has_agent_event, do: inject_default_agent_event()
    ui_event_clause = unless has_ui_event, do: inject_default_ui_event()

    quote do
      unquote(event_clauses)
      unquote(info_clauses)
      unquote(agent_event_clause)
      unquote(ui_event_clause)
    end
  end

  defp inject_handle_event(has_existing) do
    overridable =
      if has_existing do
        quote do
          defoverridable handle_event: 3
        end
      end

    fallthrough =
      if has_existing do
        quote do
          def handle_event(event, params, socket), do: super(event, params, socket)
        end
      end

    quote do
      unquote(overridable)

      def handle_event("omni:" <> _ = event, params, socket) do
        OmniUI.Handlers.handle_event(event, params, socket)
      end

      unquote(fallthrough)
    end
  end

  defp inject_handle_info(has_existing) do
    overridable =
      if has_existing do
        quote do
          defoverridable handle_info: 2
        end
      end

    fallthrough =
      if has_existing do
        quote do
          def handle_info(message, socket), do: super(message, socket)
        end
      end

    quote do
      unquote(overridable)

      def handle_info({OmniUI, :new_message, _message} = msg, socket) do
        OmniUI.Handlers.handle_info(msg, socket)
      end

      def handle_info({OmniUI, :edit_message, _turn_id, _message} = msg, socket) do
        OmniUI.Handlers.handle_info(msg, socket)
      end

      def handle_info({:agent, _pid, event, data}, socket) do
        socket = OmniUI.Handlers.handle_agent_event(event, data, socket)

        socket =
          case __MODULE__.agent_event(event, data, socket) do
            %Phoenix.LiveView.Socket{} = s ->
              s

            other ->
              raise "#{inspect(__MODULE__)}.agent_event/3 must return a socket, got: #{inspect(other)}"
          end

        {:noreply, socket}
      end

      unquote(fallthrough)
    end
  end

  defp inject_default_agent_event do
    quote do
      @impl OmniUI
      def agent_event(_event, _data, socket), do: socket
    end
  end

  defp inject_default_ui_event do
    quote do
      @impl OmniUI
      def ui_event(_event, _data, socket), do: socket
    end
  end

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Dispatches a UI event to the consuming LiveView's `ui_event/3` callback.

  Internal — called by `OmniUI.Handlers` after handling a UI event the
  macro is responsible for. Returns the (possibly mutated) socket.
  """
  @spec fire_ui_event(Phoenix.LiveView.Socket.t(), atom(), term()) ::
          Phoenix.LiveView.Socket.t()
  def fire_ui_event(%Phoenix.LiveView.Socket{view: view} = socket, event, data) do
    case view.ui_event(event, data, socket) do
      %Phoenix.LiveView.Socket{} = s ->
        s

      other ->
        raise "#{inspect(view)}.ui_event/3 must return a socket, got: #{inspect(other)}"
    end
  end

  @doc """
  Initialises the OmniUI agent system on a socket.

  Called in `mount/3`. Returns the socket with all OmniUI assigns populated
  and the `:turns` stream initialised.

  ## Options

    * `:model` (required) — `%Omni.Model{}` struct or `{provider_id, model_id}` tuple
    * `:tree` — `%OmniUI.Tree{}` to restore a conversation (default: empty tree)
    * `:thinking` — thinking mode: `false | :low | :medium | :high | :max` (default: `false`)
    * `:system` — system prompt string (default: `nil`)
    * `:tools` — list of tool entries (default: `[]`). Each entry is either:
      * a bare `%Omni.Tool{}` struct (rendered with the default content block), or
      * `{%Omni.Tool{}, opts}` where `opts` is a keyword list. The only supported
        option is `component: (assigns -> rendered)` — a 1-arity function component
        that replaces the default content block rendering for that tool's uses.
  ## Example

      def mount(_params, _session, socket) do
        {:ok, start_agent(socket,
          model: {:anthropic, "claude-sonnet-4-20250514"},
          system: "You are a helpful assistant.",
          thinking: :high
        )}
      end
  """
  @spec start_agent(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def start_agent(socket, opts) do
    model = resolve_model!(Keyword.fetch!(opts, :model))
    tree = Keyword.get(opts, :tree, %OmniUI.Tree{})
    thinking = Keyword.get(opts, :thinking, false)
    system = Keyword.get(opts, :system)
    {tools, tool_components} = normalise_tools(Keyword.get(opts, :tools, []))
    tool_timeout = Keyword.get(opts, :tool_timeout)

    agent_opts =
      [model: model, messages: OmniUI.Tree.messages(tree), opts: [thinking: thinking]]
      |> maybe_put(:system, system)
      |> maybe_put(:tools, tools)
      |> maybe_put(:tool_timeout, tool_timeout)

    {:ok, agent} = Omni.Agent.start_link(agent_opts)

    turns = OmniUI.Turn.all(tree)
    usage = OmniUI.Tree.usage(tree)

    socket
    |> assign(
      agent: agent,
      tree: tree,
      current_turn: nil,
      model: model,
      thinking: thinking,
      usage: usage,
      tool_components: tool_components
    )
    |> stream(:turns, turns)
  end

  @doc """
  Updates agent configuration on a running system.

  Accepts any subset of options. For each provided option, updates the
  appropriate combination of socket assign and agent state.

  ## Options

    * `:model` — updates both socket assign and agent model
    * `:thinking` — updates both socket assign and agent opts
    * `:system` — updates agent context only (not surfaced in UI)
    * `:tools` — updates agent context and the `:tool_components` assign. Accepts
      the same list shape as `start_agent/2` — bare structs or `{tool, opts}` tuples.
  ## Example

      OmniUI.update_agent(socket, model: {:anthropic, "claude-opus-4-20250514"})
  """
  @spec update_agent(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def update_agent(socket, opts) do
    agent = socket.assigns.agent

    Enum.reduce(opts, socket, fn
      {:model, value}, socket ->
        # A bad model ref here usually means a session persisted a model that
        # has since been deregistered (renamed, provider removed, etc.). Skip
        # the update and keep the current model rather than raising.
        # TODO: surface this to the user via a notification once the
        # notifications system lands (see roadmap § Polish & Release).
        case resolve_model(value) do
          {:ok, model} ->
            :ok = Omni.Agent.set_state(agent, :model, model)
            assign(socket, :model, model)

          {:error, reason} ->
            require Logger

            Logger.warning(
              "update_agent: ignoring unresolvable model #{inspect(value)} (#{inspect(reason)})"
            )

            socket
        end

      {:thinking, thinking}, socket ->
        :ok = Omni.Agent.set_state(agent, :opts, &Keyword.put(&1, :thinking, thinking))
        assign(socket, :thinking, thinking)

      {:system, system}, socket ->
        :ok = Omni.Agent.set_state(agent, :context, &%{&1 | system: system})
        socket

      {:tools, entries}, socket ->
        {tools, tool_components} = normalise_tools(entries)
        :ok = Omni.Agent.set_state(agent, :context, &%{&1 | tools: tools})
        assign(socket, :tool_components, tool_components)

      {:tree, tree}, socket ->
        :ok = Omni.Agent.set_state(agent, :context, &%{&1 | messages: OmniUI.Tree.messages(tree)})
        :ok = Omni.Agent.set_state(agent, :meta, %{})

        socket
        |> assign(tree: tree, current_turn: nil, usage: OmniUI.Tree.usage(tree))
        |> stream(:turns, OmniUI.Turn.all(tree), reset: true)
    end)
  end

  # ── Private ────────────────────────────────────────────────────────

  @doc false
  # Splits a list of tool entries into a flat `[%Omni.Tool{}]` list (for the
  # agent) and a `%{tool_name => component_fun}` map (for the UI). Accepts
  # either bare `%Omni.Tool{}` structs or `{%Omni.Tool{}, opts}` tuples where
  # `opts[:component]` is a 1-arity function component. Order of the flat tool
  # list is preserved. Public (undocumented) for testability.
  def normalise_tools(entries) do
    {tools, components} =
      Enum.reduce(entries, {[], %{}}, fn
        %Omni.Tool{} = tool, {tools, components} ->
          {[tool | tools], components}

        {%Omni.Tool{} = tool, opts}, {tools, components} when is_list(opts) ->
          components =
            case Keyword.get(opts, :component) do
              nil -> components
              fun when is_function(fun, 1) -> Map.put(components, tool.name, fun)
            end

          {[tool | tools], components}
      end)

    {Enum.reverse(tools), components}
  end

  defp resolve_model!(model) do
    case resolve_model(model) do
      {:ok, model} -> model
      {:error, reason} -> raise ArgumentError, "failed to resolve model: #{inspect(reason)}"
    end
  end

  defp resolve_model(%Omni.Model{} = model), do: {:ok, model}
  defp resolve_model({provider_id, model_id}), do: Omni.get_model(provider_id, model_id)
end
