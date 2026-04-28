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
          {:ok, start_session(socket,
            model: {:anthropic, "claude-sonnet-4-20250514"},
            store: {Omni.Session.Store.FileSystem, base_path: "priv/sessions"}
          )}
        end

        # Optional: observe agent events after default handling
        @impl OmniUI
        def agent_event(:turn, {:stop, response}, socket) do
          MyApp.Analytics.track(response.usage)
          socket
        end

        def agent_event(_event, _data, socket), do: socket
      end

  The macro:

  - Imports `OmniUI.Components` and `start_session/2` / `update_session/2`
  - Injects `handle_event/3` clauses for OmniUI-namespaced events
  - Injects `handle_info/2` clauses for session streaming and component messages
  - Wraps developer-defined handlers via `defoverridable` so OmniUI events
    are dispatched first and unrecognised events fall through
  - Injects a default `agent_event/3` pass-through if the developer doesn't define one

  Persistence is handled by `Omni.Session` itself — the LiveView mirrors the
  session's tree from `:tree` events and observes `:store` events for save
  outcomes.
  """

  import Phoenix.Component
  import Phoenix.LiveView, only: [stream: 4]
  import Omni.Util, only: [maybe_put: 3]

  # ── Behaviour ─────────────────────────────────────────────────────

  @doc """
  Called after OmniUI's default handling for session events.

  Receives the event type, event data, and the already-updated socket.
  Must return the socket (possibly with additional assign mutations).
  """
  @callback agent_event(event :: atom(), data :: term(), Phoenix.LiveView.Socket.t()) ::
              Phoenix.LiveView.Socket.t()

  # ── Macro ──────────────────────────────────────────────────────────

  defmacro __using__(_opts) do
    quote do
      @behaviour OmniUI
      @before_compile OmniUI
      import OmniUI.Components
      import OmniUI, only: [start_session: 2, update_session: 2, notify: 2, notify: 3]
    end
  end

  defmacro __before_compile__(env) do
    has_handle_event = Module.defines?(env.module, {:handle_event, 3})
    has_handle_info = Module.defines?(env.module, {:handle_info, 2})
    has_agent_event = Module.defines?(env.module, {:agent_event, 3})

    event_clauses = inject_handle_event(has_handle_event)
    info_clauses = inject_handle_info(has_handle_info)
    agent_event_clause = unless has_agent_event, do: inject_default_agent_event()

    quote do
      unquote(event_clauses)
      unquote(info_clauses)
      unquote(agent_event_clause)
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

      def handle_info({OmniUI, :notify, _notification} = msg, socket) do
        OmniUI.Handlers.handle_info(msg, socket)
      end

      def handle_info({OmniUI, :dismiss_notification, _id} = msg, socket) do
        OmniUI.Handlers.handle_info(msg, socket)
      end

      def handle_info({:session, _pid, event, data}, socket) do
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

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Starts an `Omni.Session` and initialises the OmniUI assigns on a socket.

  Called in `mount/3` (or `handle_params/3`). Returns the socket with all
  OmniUI assigns populated and the `:turns` stream initialised from the
  session's snapshot.

  ## Options

    * `:model` (required) — `%Omni.Model{}` struct or `{provider_id, model_id}` tuple
    * `:store` (required) — `Omni.Session.Store` adapter tuple `{module, opts}`
    * `:load` — session id to load. When absent, a new session is created with
      an auto-generated id.
    * `:thinking` — thinking mode: `false | :low | :medium | :high | :max` (default: `false`)
    * `:system` — system prompt string (default: `nil`)
    * `:tools` — list of tool entries (default: `[]`). Each entry is either:
      * a bare `%Omni.Tool{}` struct (rendered with the default content block), or
      * `{%Omni.Tool{}, opts}` where `opts` is a keyword list. The only supported
        option is `component: (assigns -> rendered)` — a 1-arity function component
        that replaces the default content block rendering for that tool's uses.
    * `:tool_timeout` — per-tool execution timeout in ms

  ## Example

      def handle_params(_params, _uri, socket) do
        {:noreply, start_session(socket,
          model: {:anthropic, "claude-sonnet-4-20250514"},
          store: {Omni.Session.Store.FileSystem, base_path: "priv/sessions"},
          system: "You are a helpful assistant.",
          thinking: :high
        )}
      end
  """
  @spec start_session(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def start_session(socket, opts) do
    model = resolve_model!(Keyword.fetch!(opts, :model))
    store = Keyword.fetch!(opts, :store)
    load = Keyword.get(opts, :load)
    thinking = Keyword.get(opts, :thinking, false)
    system = Keyword.get(opts, :system)
    {tools, tool_components} = normalise_tools(Keyword.get(opts, :tools, []))
    tool_timeout = Keyword.get(opts, :tool_timeout)

    agent_opts =
      [model: model, opts: [thinking: thinking]]
      |> maybe_put(:system, system)
      |> maybe_put(:tools, tools)
      |> maybe_put(:tool_timeout, tool_timeout)

    session_opts =
      [agent: agent_opts, store: store, subscribe: true]
      |> maybe_put(:load, load)

    {:ok, session} = Omni.Session.start_link(session_opts)
    snapshot = Omni.Session.get_snapshot(session)

    resolved_model = snapshot.agent.state.model
    resolved_thinking = Keyword.get(snapshot.agent.state.opts, :thinking, thinking)

    turns = OmniUI.Turn.all(snapshot.tree)
    usage = Omni.Session.Tree.usage(snapshot.tree)

    socket
    |> assign(
      session: session,
      session_id: snapshot.id,
      title: snapshot.title,
      tree: snapshot.tree,
      current_turn: nil,
      model: resolved_model,
      thinking: resolved_thinking,
      usage: usage,
      tool_components: tool_components,
      notification_ids: [],
      url_synced: not is_nil(load)
    )
    |> stream(:turns, turns, reset: true)
    |> stream(:notifications, [], reset: true)
  end

  @doc """
  Updates session/agent configuration on a running system.

  Accepts any subset of options. For each provided option, updates the
  appropriate combination of socket assign and session state.

  ## Options

    * `:model` — updates both socket assign and the session's agent model
    * `:thinking` — updates both socket assign and the session's agent opts
    * `:system` — updates the session's agent system prompt (not surfaced in UI)
    * `:tools` — updates the session's agent tools and the `:tool_components` assign

  ## Example

      OmniUI.update_session(socket, model: {:anthropic, "claude-opus-4-20250514"})
  """
  @spec update_session(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def update_session(socket, opts) do
    session = socket.assigns.session

    Enum.reduce(opts, socket, fn
      {:model, value}, socket ->
        # A bad model ref here usually means a session persisted a model that
        # has since been deregistered (renamed, provider removed, etc.). Skip
        # the update and keep the current model rather than raising.
        case resolve_model(value) do
          {:ok, model} ->
            :ok = Omni.Session.set_agent(session, :model, model)
            assign(socket, :model, model)

          {:error, reason} ->
            require Logger

            Logger.warning(
              "update_session: ignoring unresolvable model #{inspect(value)} (#{inspect(reason)})"
            )

            notify(:warning, "Previous model is no longer available — keeping the current model.")
            socket
        end

      {:thinking, thinking}, socket ->
        :ok = Omni.Session.set_agent(session, :opts, &Keyword.put(&1, :thinking, thinking))
        assign(socket, :thinking, thinking)

      {:system, system}, socket ->
        :ok = Omni.Session.set_agent(session, :system, system)
        socket

      {:tools, entries}, socket ->
        {tools, tool_components} = normalise_tools(entries)
        :ok = Omni.Session.set_agent(session, :tools, tools)
        assign(socket, :tool_components, tool_components)
    end)
  end

  @doc """
  Pushes a notification to the calling LiveView's toaster.

  Must be called from within the LiveView process (including from child
  LiveComponents, whose `self()` is the parent LiveView). The LiveView must
  be using `use OmniUI` — the macro injects the `handle_info` clauses that
  receive the message, and `start_session/2` initialises the stream.

  If the consumer does not render `<.notifications>` in their template, the
  notification is still accepted and auto-dismissed but is not visible.

  ## Levels

    * `:info` — neutral informational message
    * `:success` — confirmation of a completed action
    * `:warning` — something went wrong but was handled
    * `:error` — something failed

  ## Options

    * `:timeout` — ms until auto-dismiss (default `5000`)

  ## Example

      OmniUI.notify(:warning, "Couldn't auto-generate a title.")
      OmniUI.notify(:error, "Save failed", timeout: 10_000)
  """
  @spec notify(OmniUI.Notification.level(), String.t(), keyword()) :: :ok
  def notify(level, message, opts \\ [])
      when level in [:info, :success, :warning, :error] do
    send(self(), {OmniUI, :notify, OmniUI.Notification.new(level, message, opts)})
    :ok
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
