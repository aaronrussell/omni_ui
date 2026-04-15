defmodule OmniUI.AgentLive do
  use Phoenix.LiveView
  use OmniUI
  require Logger

  alias OmniUI.Artifacts
  alias OmniUI.Store

  @default_model {:ollama, "gemma4:latest"}
  # @default_model {:opencode, "kimi-k2.5"}
  @title_strategy Application.compile_env(:omni, [__MODULE__, :title_generation])

  attr :current_turn, OmniUI.Turn
  attr :usage, Omni.Usage, required: true
  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="relative h-screen flex bg-omni-bg text-omni-text">
      <div
        class={[
          "flex flex-col h-full",
          if(@view_artifacts, do: "w-1/2", else: "w-full")
        ]}>
        <.header title={@title} view_artifacts={@view_artifacts} />

        <div class="flex-1 min-h-0">
          <.chat_interface>
            <.message_list id="turns" phx-update="stream">
              <%
                # Tree node ids are per-tree, so sessions share dom_ids —
                # which would mean shared TurnComponent instances and leaked
                # state across session switches. The outer div keeps the
                # stream's dom_id (required by phx-update="stream"); the
                # LiveComponent's id is session-scoped so each session gets
                # its own instances.
              %>
              <div :for={{dom_id, turn} <- @streams.turns} id={dom_id}>
                <.live_component
                  module={OmniUI.TurnComponent}
                  id={"#{@session_id}:#{turn.id}"}
                  turn={turn}
                  tool_components={@tool_components} />
              </div>
            </.message_list>

            <.turn :if={@current_turn} id="current-turn">
              <:user>
                <.user_message text={@current_turn.user_text} attachments={@current_turn.user_attachments} />
                <.timestamp time={@current_turn.user_timestamp} />
              </:user>
              <:assistant>
                <.assistant_message
                  content={@current_turn.content}
                  tool_results={@current_turn.tool_results}
                  tool_components={@tool_components}
                  streaming={true} />
              </:assistant>
            </.turn>

            <:toolbar>
              <.toolbar
                model={@model}
                model_options={@model_options}
                thinking={@thinking}
                usage={@usage} />
            </:toolbar>

            <:footer>
              <p>Boring footer here. <a href="#todo">Privacy Policy</a></p>
            </:footer>
          </.chat_interface>
        </div>
      </div>

      <div
        :if={@view_artifacts}
        class="h-full w-1/2 border-l border-omni-border-2 shadow-[-4px_0px_6px_-1px_rgba(0,0,0,0.1)]">
        <.live_component
          module={Artifacts.PanelComponent}
          id="artifacts-panel"
          session_id={@session_id} />
      </div>

      <div
        :if={@view_sessions}
        class="fixed inset-0 bg-black/40 z-10">
        <div class="h-full w-80 bg-omni-bg border-r border-omni-border-2 shadow-[4px_0px_6px_-1px_rgba(0,0,0,0.1)]">
          <.live_component
            module={OmniUI.SessionsComponent}
            id="sessions"
            current_id={@session_id} />
        </div>
      </div>

      <.notifications stream={@streams.notifications} />
    </div>
    """
  end

  attr :title, :string
  attr :view_artifacts, :boolean, required: true

  defp header(assigns) do
    ~H"""
    <div class="grid grid-cols-[1fr_auto_1fr] gap-2 h-12 px-4 border-b border-omni-border-3">
      <div class="flex items-center gap-1">
        <button
          class={[
            "flex items-center justify-center size-8 rounded cursor-pointer",
            "text-omni-text-1 hover:text-omni-accent-1 hover:bg-omni-accent-2/10"
          ]}
          title="Sessions"
          phx-click="open_sessions">
          <Lucideicons.history class="size-4" />
        </button>

        <button
          class={[
            "flex items-center justify-center size-8 rounded cursor-pointer",
            "text-omni-text-1 hover:text-omni-accent-1 hover:bg-omni-accent-2/10"
          ]}
          title="New session"
          phx-click="new_session">
          <Lucideicons.plus class="size-4" />
        </button>
      </div>

      <form phx-submit="save_title" class="flex items-center justify-center">
        <input
          type="text"
          name="title"
          value={@title || ""}
          placeholder="Untitled"
          phx-blur="save_title"
          autocomplete="off"
          class={[
            "field-sizing-content min-w-18 max-w-80 px-2 py-1.5 text-ellipsis overflow-hidden",
            "bg-transparent border-0 outline-none text-center text-sm",
            "text-omni-text-1 placeholder:text-omni-text-1 focus:placeholder:opacity-0",
            "hover:bg-omni-accent-2/10 focus:text-omni-text focus:bg-omni-accent-2/10 focus:max-w-none"
          ]} />
      </form>

      <div class="flex items-center justify-end gap-1">
        <button
          class={[
            "flex items-center justify-center size-8 rounded cursor-pointer",
            "text-omni-text-1 hover:text-omni-accent-1 hover:bg-omni-accent-2/10"
          ]}
          title={if(@view_artifacts, do: "Close artifacts panel", else: "Open artifacts panel")}
          phx-click="toggle_artifacts">
          <Lucideicons.panel_right_open :if={not @view_artifacts} class="size-4" />
          <Lucideicons.panel_right_close :if={@view_artifacts} class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, models1} = Omni.list_models(:ollama)
    {:ok, models2} = Omni.list_models(:opencode)
    models = models1 ++ models2

    socket =
      socket
      |> assign(
        session_id: nil,
        title: nil,
        model_options: models,
        view_artifacts: false,
        view_sessions: false
      )
      |> start_agent(model: @default_model, tool_timeout: 120_000)

    {:ok, socket}
  end

  # Re-entry guard: push_patch triggers handle_params with the same session_id
  @impl Phoenix.LiveView
  def handle_params(%{"session_id" => id}, _uri, socket) when socket.assigns.session_id == id do
    {:noreply, socket}
  end

  # Load existing session
  def handle_params(%{"session_id" => session_id}, _uri, socket) do
    if connected?(socket) do
      case Store.load(session_id) do
        {:ok, tree, metadata} ->
          model = Map.get(metadata, :model, @default_model)
          thinking = Map.get(metadata, :thinking, false)
          title = Map.get(metadata, :title)

          socket =
            socket
            |> assign(session_id: session_id, title: title)
            |> update_agent(
              tree: tree,
              model: model,
              thinking: thinking,
              tools: create_tools(session_id)
            )

          {:noreply, socket}

        {:error, _} ->
          {:noreply, push_navigate(socket, to: "/")}
      end
    else
      {:noreply, socket}
    end
  end

  # New session: generate ID and patch URL
  def handle_params(_params, _uri, socket) do
    if connected?(socket) do
      {:noreply, start_new_session(socket, replace: true)}
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_artifacts", _, socket) do
    {:noreply, assign(socket, :view_artifacts, !socket.assigns.view_artifacts)}
  end

  def handle_event("open_sessions", _, socket) do
    {:noreply, assign(socket, :view_sessions, true)}
  end

  def handle_event("close_sessions", _, socket) do
    {:noreply, assign(socket, :view_sessions, false)}
  end

  def handle_event("switch_session", %{"session-id" => session_id}, socket) do
    {:noreply,
     socket
     |> assign(:view_sessions, false)
     |> push_patch(to: "/?session_id=#{session_id}")}
  end

  def handle_event("new_session", _, socket) do
    {:noreply, start_new_session(socket)}
  end

  def handle_event("save_title", %{"title" => title}, socket),
    do: {:noreply, maybe_save_title(socket, title)}

  def handle_event("save_title", %{"value" => title}, socket),
    do: {:noreply, maybe_save_title(socket, title)}

  def handle_event("view_artifact", %{"filename" => filename}, socket) do
    send_update(Artifacts.PanelComponent,
      id: "artifacts-panel",
      action: {:view, filename}
    )

    {:noreply, assign(socket, :view_artifacts, true)}
  end

  @impl Phoenix.LiveView
  def handle_info({OmniUI, :active_session_deleted}, socket) do
    {:noreply, start_new_session(socket)}
  end

  @impl OmniUI
  def agent_event(:tool_result, %{name: tool_name}, socket)
      when tool_name in ["artifacts", "repl"] do
    send_update(Artifacts.PanelComponent, id: "artifacts-panel", action: :rescan)
    socket
  end

  def agent_event(:stop, _response, socket) do
    Store.save_tree(socket.assigns.session_id, socket.assigns.tree)
    maybe_generate_title(socket, @title_strategy)
  end

  def agent_event(_event, _data, socket), do: socket

  @impl OmniUI
  def ui_event(:model_changed, model, socket) do
    Store.save_metadata(socket.assigns.session_id, model: Omni.Model.to_ref(model))
    socket
  end

  def ui_event(:thinking_changed, thinking, socket) do
    Store.save_metadata(socket.assigns.session_id, thinking: thinking)
    socket
  end

  def ui_event(_event, _data, socket), do: socket

  @impl Phoenix.LiveView
  def handle_async(:generate_title, {:ok, {:ok, title}}, socket) do
    socket =
      if socket.assigns.title == nil do
        Store.save_metadata(socket.assigns.session_id, title: title)
        assign(socket, :title, title)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_async(:generate_title, {:ok, {:error, reason}}, socket) do
    notify(:warning, "Title generation failed.")
    {:noreply, socket}
  end

  def handle_async(:generate_title, {:exit, reason}, socket) do
    #Logger.error("Title generation crashed: #{inspect(reason)}")
    notify(:warning, "Title generation failed.")
    {:noreply, socket}
  end

  defp maybe_generate_title(socket, nil), do: socket

  defp maybe_generate_title(socket, :main),
    do: maybe_generate_title(socket, Omni.Model.to_ref(socket.assigns.model))

  defp maybe_generate_title(socket, strategy) do
    case socket.assigns.title do
      nil ->
        messages = OmniUI.Tree.messages(socket.assigns.tree)
        start_async(socket, :generate_title, fn -> OmniUI.Title.generate(strategy, messages) end)

      _ ->
        socket
    end
  end

  defp maybe_save_title(socket, input) do
    title = input |> to_string() |> String.trim()
    current = socket.assigns.title || ""

    cond do
      title == current ->
        socket

      title == "" ->
        Store.save_metadata(socket.assigns.session_id, title: nil)
        assign(socket, :title, nil)

      true ->
        Store.save_metadata(socket.assigns.session_id, title: title)
        assign(socket, :title, title)
    end
  end

  defp start_new_session(socket, opts \\ []) do
    if socket.assigns.current_turn do
      Omni.Agent.cancel(socket.assigns.agent)
    end

    session_id = generate_session_id()

    socket
    |> assign(session_id: session_id, title: nil)
    |> update_agent(tree: %OmniUI.Tree{}, tools: create_tools(session_id))
    |> push_patch(to: "/?session_id=#{session_id}", replace: Keyword.get(opts, :replace, false))
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end

  defp create_tools(session_id) do
    [
      {Artifacts.Tool.new(session_id: session_id), component: &Artifacts.ChatUI.tool_use/1},
      {OmniUI.REPL.Tool.new(
         extensions: [
           {Artifacts.REPLExtension, [session_id: session_id]}
         ]
       ), component: &OmniUI.REPL.ChatUI.tool_use/1}
    ]
  end
end
