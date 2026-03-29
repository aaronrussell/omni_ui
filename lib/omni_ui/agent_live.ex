defmodule OmniUI.AgentLive do
  use Phoenix.LiveView
  use OmniUI

  attr :current_turn, OmniUI.Turn
  attr :usage, Omni.Usage, required: true
  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="relative size-full flex">
      <div class="h-full w-full">
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

      <div class="h-full hidden">
        <!-- TODO : artifacts panel -->
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, models1} = Omni.list_models(:anthropic)
    {:ok, models2} = Omni.list_models(:ollama)

    socket =
      socket
      |> assign(model_options: models1 ++ models2)
      |> start_agent(
        tree: OmniUI.TreeFaker.generate(),
        model: {:ollama, "qwen3.5:4b"}
      )

    {:ok, socket}
  end
end
