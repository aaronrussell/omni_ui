defmodule OmniUI.AgentLive do
  use Phoenix.LiveView
  use OmniUI

  alias OmniUI.Artifacts

  @default_model {:ollama, "gemma4:e4b"}
  @default_model {:opencode, "kimi-k2.5"}

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
        <.header view_artifacts={@view_artifacts} />

        <div class="flex-1 min-h-0">
          <.chat_interface>
            <.message_list id="turns" phx-update="stream">
              <.live_component
                :for={{dom_id, turn} <- @streams.turns}
                module={OmniUI.TurnComponent}
                id={dom_id}
                turn={turn}
                tool_components={@tool_components} />
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
        class={[
          "h-full w-1/2 border-l border-omni-border-2 shadow-[-4px_0px_6px_-1px_rgba(0,0,0,0.1)]",
          if(@view_artifacts, do: "block", else: "hidden")
        ]}>
        <.live_component
          :if={@view_artifacts}
          module={Artifacts.PanelComponent}
          id="artifacts-panel"
          session_id={@session_id} />
      </div>
    </div>
    """
  end

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
          title="Sessions">
          <Lucideicons.history class="size-4" />
        </button>

        <button
          class={[
            "flex items-center justify-center size-8 rounded cursor-pointer",
            "text-omni-text-1 hover:text-omni-accent-1 hover:bg-omni-accent-2/10"
          ]}
          title="New sessions">
          <Lucideicons.plus class="size-4" />
        </button>
      </div>

      <div class="flex items-center justify-center">
        <span class="text-sm text-omni-text-1">Untitled</span>
      </div>

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
    {:ok, models1} = Omni.list_models(:anthropic)
    {:ok, models2} = Omni.list_models(:opencode)
    models = models1 ++ models2

    socket =
      socket
      |> assign(session_id: nil, model_options: models, view_artifacts: false)
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
      case load_session(session_id) do
        {:ok, tree, metadata} ->
          model = Keyword.get(metadata, :model, @default_model)
          thinking = Keyword.get(metadata, :thinking, false)

          socket =
            socket
            |> assign(session_id: session_id)
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
      session_id = generate_session_id()

      socket =
        socket
        |> assign(session_id: session_id)
        |> update_agent(tools: create_tools(session_id))
        |> push_patch(to: "/?session_id=#{session_id}", replace: true)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_artifacts", _, socket) do
    {:noreply, assign(socket, :view_artifacts, !socket.assigns.view_artifacts)}
  end

  def handle_event("view_artifact", %{"filename" => filename}, socket) do
    send_update(Artifacts.PanelComponent,
      id: "artifacts-panel",
      action: {:view, filename}
    )

    {:noreply, assign(socket, :view_artifacts, true)}
  end

  @impl OmniUI
  def agent_event(:tool_result, %{name: tool_name}, socket)
      when tool_name in ["artifacts", "repl"] do
    send_update(Artifacts.PanelComponent, id: "artifacts-panel", action: :rescan)
    socket
  end

  def agent_event(:stop, _response, socket) do
    %{session_id: session_id, tree: tree, model: model, thinking: thinking} = socket.assigns

    save_tree(session_id, tree)
    save_metadata(session_id, model: Omni.Model.to_ref(model), thinking: thinking)

    socket
  end

  def agent_event(_event, _data, socket), do: socket

  defp generate_session_id do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end

  defp create_tools(session_id) do
    [
      {Artifacts.Tool.new(session_id: session_id), component: &Artifacts.ChatUI.tool_use/1},
      OmniUI.REPL.Tool.new(
        extensions: [
          {Artifacts.REPLExtension, [session_id: session_id]}
        ]
      )
    ]
  end
end
