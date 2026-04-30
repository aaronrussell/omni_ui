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
          {:ok, init_session(socket, model: {:anthropic, "claude-sonnet-4-5"})}
        end

        def handle_params(params, _uri, socket) do
          {:noreply, attach_session(socket, id: params["session_id"])}
        end

        # Optional: observe agent events after default handling
        @impl OmniUI
        def agent_event(:turn, {:stop, response}, socket) do
          MyApp.Analytics.track(response.usage)
          socket
        end

        def agent_event(_event, _data, socket), do: socket
      end

  Sessions are supervised by an `Omni.Session.Manager`. OmniUI ships
  `OmniUI.Sessions` as the default Manager — add it to your application
  supervision tree with a configured store, then `attach_session/2` will
  use it automatically. Custom Managers can be passed via the `:manager`
  option to `init_session/2`.

  ## State ownership

  Two sets of assigns live on a LiveView using `OmniUI`:

  - **OmniUI-owned**: session lifecycle (`:session`, `:session_id`,
    `:title`, `:tree`, `:current_turn`), agent config (`:manager`,
    `:agent_module`, `:model`, `:thinking`, `:system`, `:tools`,
    `:tool_timeout`, `:tool_components`), UI state (`:usage`,
    `:url_synced`, `:notification_ids`), and the `:turns` and
    `:notifications` streams. Initialised by `init_session/2`
    in `mount/3`; mutated by `attach_session/2`, `ensure_session/1`,
    `update_session/2`, and the macro-injected handlers.
  - **Consumer-owned**: anything else — UI-driven state (`:model_options`,
    view toggles, etc.), application data, custom event handlers, routing.

  The rule: if `mount/3` is setting an OmniUI-owned assign directly,
  reach for `init_session/2` instead.

  ## Macro behaviour

  - Imports every public function from `OmniUI` and all of `OmniUI.Components`
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
  import Phoenix.LiveView, only: [stream: 3, stream: 4]
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

      import OmniUI,
        only: [
          init_session: 2,
          attach_session: 2,
          ensure_session: 1,
          update_session: 2,
          notify: 2,
          notify: 3
        ]
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

      def handle_info({:session, pid, event, data}, socket) do
        # Drop stale events from a session we've since detached from. After a
        # session switch, the old session's queued events may linger in our
        # mailbox; processing them would mutate the new session's assigns.
        if pid == socket.assigns[:session] do
          socket = OmniUI.Handlers.handle_agent_event(event, data, socket)

          socket =
            case __MODULE__.agent_event(event, data, socket) do
              %Phoenix.LiveView.Socket{} = s ->
                s

              other ->
                raise "#{inspect(__MODULE__)}.agent_event/3 must return a socket, got: #{inspect(other)}"
            end

          {:noreply, socket}
        else
          {:noreply, socket}
        end
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
  Initialises every OmniUI-owned assign and stream on the socket.

  Call this once from `mount/3`. Sets the agent-config assigns
  (`:manager`, `:model`, `:thinking`, `:system`, `:tools`, `:tool_timeout`,
  `:tool_components`), the session-state assigns (`:session`, `:session_id`,
  `:title`, `:tree`, `:current_turn`, `:usage`, `:url_synced`), the
  notification list (`:notification_ids`), and initialises the `:turns` and
  `:notifications` streams. The session itself is `nil` after this call —
  it's attached either by `attach_session/2` (when `handle_params/3`
  receives a `session_id`) or by `ensure_session/1` (lazily, on the first
  `:new_message`).

  ## Options

    * `:model` (required) — `%Omni.Model{}` struct or `{provider_id, model_id}` tuple
    * `:manager` — Manager module (default `OmniUI.Sessions`). Must be
      running under the application supervision tree with a configured store.
    * `:agent_module` — module that `use`s `Omni.Agent` (default `nil`,
      meaning the stock `Omni.Agent`). Use this to bake in tools, system
      prompt, or other defaults via the agent's `init/1` callback.
    * `:thinking` — thinking mode: `false | :low | :medium | :high | :max` (default: `false`)
    * `:system` — system prompt string (default: `nil`)
    * `:tools` — list of tool entries (default: `[]`). Each entry is either:
      * a bare `%Omni.Tool{}` struct (rendered with the default content block), or
      * `{%Omni.Tool{}, opts}` where `opts` is a keyword list. The only supported
        option is `component: (assigns -> rendered)` — a 1-arity function component
        that replaces the default content block rendering for that tool's uses.
    * `:tool_components` — map of `tool_name => (assigns -> rendered)` for tools
      that aren't constructed by the consumer (typically tools added by an
      `:agent_module`'s `init/1` callback). Merged with components extracted
      from `:tools` entries; this map wins on key conflicts.
    * `:tool_timeout` — per-tool execution timeout in ms

  ## Example

      def mount(_params, _session, socket) do
        {:ok,
         socket
         |> assign(:model_options, my_model_options())
         |> OmniUI.init_session(model: {:anthropic, "claude-sonnet-4-5"})}
      end
  """
  @spec init_session(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def init_session(socket, opts) do
    manager = Keyword.get(opts, :manager, OmniUI.Sessions)
    agent_module = Keyword.get(opts, :agent_module)
    model = resolve_model!(Keyword.fetch!(opts, :model))
    thinking = Keyword.get(opts, :thinking, false)
    system = Keyword.get(opts, :system)
    {tools, tool_components} = normalise_tools(Keyword.get(opts, :tools, []))
    tool_components = Map.merge(tool_components, Keyword.get(opts, :tool_components, %{}))
    tool_timeout = Keyword.get(opts, :tool_timeout)

    socket
    |> assign(
      manager: manager,
      agent_module: agent_module,
      model: model,
      thinking: thinking,
      system: system,
      tools: tools,
      tool_timeout: tool_timeout,
      tool_components: tool_components,
      session: nil,
      session_id: nil,
      title: nil,
      tree: nil,
      current_turn: nil,
      usage: %Omni.Usage{},
      notification_ids: [],
      url_synced: false
    )
    |> stream(:turns, [])
    |> stream(:notifications, [])
  end

  @doc """
  Attaches the LiveView to a session by id, or detaches it.

  Call from `handle_params/3` after `init_session/2` has set the defaults
  in `mount/3`. Idempotent for the same `:id` — re-entering with the
  currently-attached id is a no-op (so `push_patch` to the same URL
  doesn't churn the subscription).

  Otherwise always detaches the previous session (releasing its
  `:controller` hold so it can idle-shutdown) before applying the new
  state.

  ## Behaviour

    * **`:id` is a binary** — opens that session via the configured
      Manager, atomically subscribes-with-snapshot, and populates the
      session-state assigns. Raises if the id isn't found in the store
      (wrap in `try/rescue` to handle gracefully).
    * **`:id` is `nil` or omitted** — resets the LV to the blank state
      (no session attached). The session will be lazily created by
      `ensure_session/1` on the first `:new_message`, so refreshing on
      `/` doesn't pile up untitled draft sessions.

  Reads agent configuration (`:manager`, `:model`, `:thinking`, `:system`,
  `:tools`, `:tool_timeout`) from the assigns set by `init_session/2`.

  ## Example

      def handle_params(params, _uri, socket) do
        if connected?(socket) do
          try do
            {:noreply, attach_session(socket, id: params["session_id"])}
          rescue
            _ -> {:noreply, push_navigate(socket, to: "/")}
          end
        else
          {:noreply, socket}
        end
      end
  """
  @spec attach_session(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def attach_session(socket, opts) do
    session_id = socket.assigns[:session_id]

    case Keyword.get(opts, :id) do
      id when is_nil(id) ->
        detach_previous_session(socket)
        blank_session(socket)

      id when id == session_id ->
        socket

      id ->
        detach_previous_session(socket)
        a = socket.assigns

        agent_opts =
          build_agent_opts(
            a.agent_module,
            a.model,
            a.thinking,
            a.system,
            a.tools,
            a.tool_timeout
          )

        session = open_session!(a.manager, id, agent_opts)
        {:ok, snapshot} = Omni.Session.subscribe(session, mode: :controller)
        apply_snapshot(socket, session, snapshot, url_synced: true)
    end
  end

  @doc """
  Ensures `socket.assigns.session` is set, creating a fresh session via the
  configured Manager if it is `nil`.

  Used by the macro's `:new_message` handler to lazily create the session
  on first prompt — so a user opening `/` and refreshing doesn't spawn
  untouched draft sessions.

  Reads agent configuration from the assigns populated by `init_session/2`
  (`:manager`, `:model`, `:thinking`, `:system`, `:tools`, `:tool_timeout`).
  Subscribes the calling LiveView as `:controller` atomically with the
  snapshot.

  Returns the socket unchanged when a session is already attached.
  """
  @spec ensure_session(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def ensure_session(socket) do
    case socket.assigns[:session] do
      pid when is_pid(pid) ->
        socket

      _ ->
        a = socket.assigns

        agent_opts =
          build_agent_opts(
            a.agent_module,
            a.model,
            a.thinking,
            a.system,
            a.tools,
            a.tool_timeout
          )

        {:ok, pid} = a.manager.create(subscribe: false, agent: agent_opts)
        {:ok, snapshot} = Omni.Session.subscribe(pid, mode: :controller)
        apply_snapshot(socket, pid, snapshot, url_synced: false)
    end
  end

  defp blank_session(socket) do
    socket
    |> assign(
      session: nil,
      session_id: nil,
      title: nil,
      tree: nil,
      current_turn: nil,
      usage: %Omni.Usage{},
      url_synced: false
    )
    |> stream(:turns, [], reset: true)
  end

  defp apply_snapshot(socket, pid, snapshot, opts) do
    url_synced = Keyword.get(opts, :url_synced, false)
    resolved_model = snapshot.agent.state.model
    resolved_thinking = Keyword.get(snapshot.agent.state.opts, :thinking, socket.assigns.thinking)

    turns = OmniUI.Turn.all(snapshot.tree)
    usage = Omni.Session.Tree.usage(snapshot.tree)
    current_turn = rebuild_current_turn(snapshot)

    socket
    |> assign(
      session: pid,
      session_id: snapshot.id,
      title: snapshot.title,
      tree: snapshot.tree,
      current_turn: current_turn,
      model: resolved_model,
      thinking: resolved_thinking,
      usage: usage,
      url_synced: url_synced
    )
    |> stream(:turns, turns, reset: true)
  end

  defp build_agent_opts(agent_module, model, thinking, system, tools, tool_timeout) do
    opts =
      [model: model, opts: [thinking: thinking]]
      |> maybe_put(:system, system)
      |> maybe_put(:tools, tools)
      |> maybe_put(:tool_timeout, tool_timeout)

    case agent_module do
      nil -> opts
      mod when is_atom(mod) -> {mod, opts}
    end
  end

  # If the snapshot was taken while the agent is mid-turn, reconstruct a
  # streaming `OmniUI.Turn` from the pending messages and the in-flight
  # partial assistant message. Subsequent streaming events from the session
  # then accumulate into this turn correctly.
  defp rebuild_current_turn(snapshot) do
    case snapshot.agent.pending do
      [] ->
        nil

      [_ | _] = pending ->
        messages = pending ++ List.wrap(snapshot.agent.partial)

        nil
        |> OmniUI.Turn.new(messages, %Omni.Usage{})
        |> Map.put(:status, :streaming)
    end
  end

  # Pass `subscribe: false` to the Manager and subscribe ourselves above — the
  # explicit `Omni.Session.subscribe/2` call atomically pairs subscribe with
  # snapshot, eliminating a race where streaming events could fire between
  # Manager-internal subscribe and our subsequent `get_snapshot/1`.
  defp open_session!(manager, id, agent_opts) do
    case manager.open(id, subscribe: false, agent: agent_opts) do
      {:ok, pid, _started_or_existing} -> pid
      {:error, :not_found} -> raise "Omni.Session #{inspect(id)} not found"
    end
  end

  # Drop the controller hold on the previous session so it can idle-shutdown,
  # and stop receiving events that would race against the new session's
  # `current_turn`. Tolerant of a dead/missing prior session.
  defp detach_previous_session(socket) do
    case socket.assigns[:session] do
      nil ->
        :ok

      pid when is_pid(pid) ->
        try do
          Omni.Session.unsubscribe(pid)
        catch
          :exit, _ -> :ok
        end
    end
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

  When called before a session has been attached (e.g. the user picks a
  model on the blank `/` page before sending the first prompt), updates
  the assigns only — the value is then passed to `Omni.Session` at
  `ensure_session/1` time.
  """
  @spec update_session(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def update_session(socket, opts) do
    Enum.reduce(opts, socket, fn
      {:model, value}, socket ->
        # A bad model ref here usually means a session persisted a model that
        # has since been deregistered (renamed, provider removed, etc.). Skip
        # the update and keep the current model rather than raising.
        case resolve_model(value) do
          {:ok, model} ->
            maybe_set_agent(socket, :model, model)
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
        maybe_set_agent(socket, :opts, &Keyword.put(&1, :thinking, thinking))
        assign(socket, :thinking, thinking)

      {:system, system}, socket ->
        maybe_set_agent(socket, :system, system)
        assign(socket, :system, system)

      {:tools, entries}, socket ->
        {tools, tool_components} = normalise_tools(entries)
        maybe_set_agent(socket, :tools, tools)

        socket
        |> assign(:tools, tools)
        |> assign(:tool_components, tool_components)
    end)
  end

  defp maybe_set_agent(socket, key, value) do
    case socket.assigns[:session] do
      pid when is_pid(pid) -> Omni.Session.set_agent(pid, key, value)
      _ -> :ok
    end
  end

  @doc """
  Pushes a notification to the calling LiveView's toaster.

  Must be called from within the LiveView process (including from child
  LiveComponents, whose `self()` is the parent LiveView). The LiveView must
  be using `use OmniUI` — the macro injects the `handle_info` clauses that
  receive the message, and `attach_session/2` initialises the stream.

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
