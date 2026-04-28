defmodule OmniUI.AgentLive do
  use Phoenix.LiveView
  use OmniUI
  require Logger

  @default_model {:ollama, "gemma4:latest"}
  # @default_model {:opencode, "kimi-k2.5"}

  attr :current_turn, OmniUI.Turn
  attr :usage, Omni.Usage, required: true
  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="relative h-screen flex bg-omni-bg text-omni-text">
      <div class="flex flex-col h-full w-full">
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
    models = models1 ++ models2

    socket =
      socket
      |> assign(
        session_id: nil,
        title: nil,
        model_options: models
      )
      |> start_session(
        model: @default_model,
        store: store(),
        tool_timeout: 120_000
      )

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
      try do
        {:noreply,
         start_session(socket,
           load: session_id,
           model: @default_model,
           store: store(),
           tool_timeout: 120_000
         )}
      rescue
        e ->
          Logger.error("Failed to load session #{session_id}: #{inspect(e)}")
          {:noreply, push_navigate(socket, to: "/")}
      catch
        :exit, reason ->
          Logger.error("Failed to load session #{session_id}: #{inspect(reason)}")
          {:noreply, push_navigate(socket, to: "/")}
      end
    else
      {:noreply, socket}
    end
  end

  # New session — auto id, URL stays at "/" until first store save event
  # (handled in OmniUI.Handlers).
  def handle_params(_params, _uri, socket) do
    if connected?(socket) do
      {:noreply,
       start_session(socket,
         model: @default_model,
         store: store(),
         tool_timeout: 120_000
       )}
    else
      {:noreply, socket}
    end
  end

  defp store do
    case Application.get_env(:omni, __MODULE__, []) |> Keyword.get(:store) do
      nil ->
        raise "OmniUI.AgentLive store is not configured. " <>
                "Set config :omni, OmniUI.AgentLive, store: {Module, opts}"

      store ->
        store
    end
  end
end
