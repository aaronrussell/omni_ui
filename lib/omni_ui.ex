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
        def agent_event(:done, response, socket) do
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
  - Injects a default `agent_event/3` pass-through if the developer doesn't define one
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

  # ── Macro ──────────────────────────────────────────────────────────

  defmacro __using__(opts) do
    store = Keyword.get(opts, :store)

    quote do
      @behaviour OmniUI
      @before_compile OmniUI
      @__omni_store__ unquote(store) || Application.compile_env(:omni, [__MODULE__, :store])
      import OmniUI.Components
      import OmniUI, only: [start_agent: 2, update_agent: 2]
    end
  end

  defmacro __before_compile__(env) do
    has_handle_event = Module.defines?(env.module, {:handle_event, 3})
    has_handle_info = Module.defines?(env.module, {:handle_info, 2})
    has_agent_event = Module.defines?(env.module, {:agent_event, 3})
    store = Module.get_attribute(env.module, :__omni_store__)

    event_clauses = inject_handle_event(has_handle_event)
    info_clauses = inject_handle_info(has_handle_info)
    agent_event_clause = unless has_agent_event, do: inject_default_agent_event()
    store_clauses = inject_store_functions(store)

    quote do
      unquote(event_clauses)
      unquote(info_clauses)
      unquote(agent_event_clause)
      unquote(store_clauses)
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

  defp inject_store_functions(store) do
    quote do
      @doc false
      def save_tree(session_id, tree, opts \\ []) do
        case unquote(store) do
          nil -> :ok
          store -> apply(store, :save_tree, [session_id, tree, opts])
        end
      end

      @doc false
      def save_metadata(session_id, metadata, opts \\ []) do
        case unquote(store) do
          nil -> :ok
          store -> apply(store, :save_metadata, [session_id, metadata, opts])
        end
      end

      @doc false
      def load_session(session_id, opts \\ []) do
        case unquote(store) do
          nil -> {:error, :no_store}
          store -> apply(store, :load, [session_id, opts])
        end
      end

      @doc false
      def list_sessions(opts \\ []) do
        case unquote(store) do
          nil -> {:ok, []}
          store -> apply(store, :list, [opts])
        end
      end

      @doc false
      def delete_session(session_id, opts \\ []) do
        case unquote(store) do
          nil -> :ok
          store -> apply(store, :delete, [session_id, opts])
        end
      end
    end
  end

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Initialises the OmniUI agent system on a socket.

  Called in `mount/3`. Returns the socket with all OmniUI assigns populated
  and the `:turns` stream initialised.

  ## Options

    * `:model` (required) — `%Omni.Model{}` struct or `{provider_id, model_id}` tuple
    * `:tree` — `%OmniUI.Tree{}` to restore a conversation (default: empty tree)
    * `:thinking` — thinking mode: `false | :low | :medium | :high | :max` (default: `false`)
    * `:system` — system prompt string (default: `nil`)
    * `:tools` — list of tool modules (default: `[]`)
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
    tools = Keyword.get(opts, :tools, [])
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
      usage: usage
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
    * `:tools` — updates agent context only
  ## Example

      OmniUI.update_agent(socket, model: {:anthropic, "claude-opus-4-20250514"})
  """
  @spec update_agent(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def update_agent(socket, opts) do
    agent = socket.assigns.agent

    Enum.reduce(opts, socket, fn
      {:model, value}, socket ->
        model = resolve_model!(value)
        :ok = Omni.Agent.set_state(agent, :model, model)
        assign(socket, :model, model)

      {:thinking, thinking}, socket ->
        :ok = Omni.Agent.set_state(agent, :opts, &Keyword.put(&1, :thinking, thinking))
        assign(socket, :thinking, thinking)

      {:system, system}, socket ->
        :ok = Omni.Agent.set_state(agent, :context, &%{&1 | system: system})
        socket

      {:tools, tools}, socket ->
        :ok = Omni.Agent.set_state(agent, :context, &%{&1 | tools: tools})
        socket

      {:tree, tree}, socket ->
        :ok = Omni.Agent.set_state(agent, :context, &%{&1 | messages: OmniUI.Tree.messages(tree)})
        :ok = Omni.Agent.set_state(agent, :meta, %{})

        socket
        |> assign(tree: tree, current_turn: nil, usage: OmniUI.Tree.usage(tree))
        |> stream(:turns, OmniUI.Turn.all(tree), reset: true)
    end)
  end

  # ── Private ────────────────────────────────────────────────────────

  defp resolve_model!(%Omni.Model{} = model), do: model

  defp resolve_model!({provider_id, model_id}) do
    case Omni.get_model(provider_id, model_id) do
      {:ok, model} -> model
      {:error, reason} -> raise ArgumentError, "failed to resolve model: #{inspect(reason)}"
    end
  end
end
