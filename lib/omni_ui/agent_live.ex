defmodule OmniUI.AgentLive do
  use Phoenix.LiveView
  use OmniUI

  @default_model {:ollama, "qwen3.5:4b"}

  attr :current_turn, OmniUI.Turn
  attr :usage, Omni.Usage, required: true
  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="relative size-full flex">
      <div class="h-full w-1/2">
        <.chat_interface>
          <.message_list id="turns" phx-update="stream">
            <.live_component
              :for={{dom_id, turn} <- @streams.turns}
              module={OmniUI.TurnComponent}
              id={dom_id}
              turn={turn} />
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

      <!-- TODO : artifacts button -->

      <div class="h-full w-1/2 border-l border-omni-border-2 shadow-[-4px_0px_6px_-1px_rgba(0,0,0,0.1)]">
        <.live_component
          module={OmniUI.Artifacts.PanelComponent}
          id="artifacts-panel"
          session_id={@session_id} />
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, models1} = Omni.list_models(:anthropic)
    {:ok, models2} = Omni.list_models(:ollama)
    models = models1 ++ models2

    socket =
      socket
      |> assign(session_id: nil, model_options: models)
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

  @impl OmniUI
  def agent_event(:tool_result, %{name: tool_name}, socket)
      when tool_name in ["artifacts", "repl"] do
    send_update(OmniUI.Artifacts.PanelComponent, id: "artifacts-panel", action: :rescan)
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
      OmniUI.Artifacts.Tool.new(session_id: session_id),
      OmniUI.REPL.Tool.new(
        extensions: [
          {OmniUI.Artifacts.REPLExtension, [session_id: session_id]}
        ]
      )
    ]
  end
end
