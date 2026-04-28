defmodule OmniUI.AgentLive do
  use Phoenix.LiveView
  use OmniUI

  @default_model {:ollama, "gemma4:latest"}

  attr :current_turn, OmniUI.Turn
  attr :usage, Omni.Usage, required: true
  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="relative h-screen flex bg-omni-bg text-omni-text">
      <div class="w-64 h-full z-10 bg-omni-bg border-r border-omni-border-2 shadow-[4px_0px_6px_-1px_rgba(0,0,0,0.1)]">
        <.live_component
          module={OmniUI.SessionsComponent}
          id="sessions"
          manager={OmniUI.Sessions}
          current_id={@session_id} />
      </div>

      <div class="flex-auto flex flex-col h-full">
        <div class="flex-1 min-h-0">
          <.chat_interface>
            <.message_list id="turns" phx-update="stream">
              <div :for={{dom_id, turn} <- @streams.turns} id={dom_id}>
                <.live_component
                  module={OmniUI.TurnComponent}
                  id={"turn-#{turn.id}"}
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

      <.notifications stream={@streams.notifications} />
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, models1} = Omni.list_models(:ollama)
    {:ok, models2} = Omni.list_models(:opencode)

    if connected?(socket), do: OmniUI.Sessions.subscribe()

    {:ok,
     socket
     |> assign(:model_options, models1 ++ models2)
     |> init_session(model: @default_model, tool_timeout: 120_000)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    if connected?(socket) do
      try do
        {:noreply, attach_session(socket, id: params["session_id"])}
      rescue
        _ ->
          notify(:warning, "Session not found.")
          {:noreply, push_patch(socket, to: "/")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("switch_session", %{"session-id" => id}, socket) do
    {:noreply, push_patch(socket, to: "/?session_id=#{id}")}
  end

  def handle_event("new_session", _params, socket) do
    {:noreply, push_patch(socket, to: "/")}
  end

  @impl Phoenix.LiveView
  def handle_info({:manager, _, _, _} = msg, socket) do
    send_update(OmniUI.SessionsComponent, id: "sessions", manager_event: msg)
    {:noreply, socket}
  end

  def handle_info({OmniUI, :active_session_deleted}, socket) do
    {:noreply, push_patch(socket, to: "/")}
  end
end
