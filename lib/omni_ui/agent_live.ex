defmodule OmniUI.AgentLive do
  use Phoenix.LiveView
  use OmniUI

  alias OmniUI.Artifacts

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
        <.header title={@title} />
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
                <.timestamp
                  class="text-xs text-omni-text-4"
                  time={@current_turn.user_timestamp} />
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
        class="h-full w-[calc(50%-8rem)] border-l border-omni-border-2 shadow-[-4px_0px_6px_-1px_rgba(0,0,0,0.1)]">
        <.live_component
          module={Artifacts.PanelComponent}
          id="artifacts-panel"
          session_id={@session_id} />
      </div>

      <.notifications stream={@streams.notifications} />
    </div>
    """
  end

  attr :title, :string, default: nil

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
          title="Open artifacts panel">
          <Lucideicons.panel_right_open class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, models1} = Omni.list_models(:ollama)
    {:ok, models2} = Omni.list_models(:alibaba)
    {:ok, models3} = Omni.list_models(:opencode)

    if connected?(socket), do: OmniUI.Sessions.subscribe()

    {:ok,
     socket
     |> assign(:model_options, models1 ++ models2 ++ models3)
     |> init_session(
       agent_module: OmniUI.AgentLive.Agent,
       tool_components: %{
         "artifacts" => &OmniUI.Artifacts.ChatUI.tool_use/1,
         "repl" => &OmniUI.REPL.ChatUI.tool_use/1
       },
       model: @default_model,
       tool_timeout: 120_000
     )}
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

  # phx-submit sends form fields keyed by `name`; phx-blur sends the input's value as `"value"`.
  def handle_event("save_title", %{"title" => raw}, socket) do
    save_title(socket.assigns.session, raw)
    {:noreply, socket}
  end

  def handle_event("save_title", %{"value" => raw}, socket) do
    save_title(socket.assigns.session, raw)
    {:noreply, socket}
  end

  def handle_event("open_artifact", %{"filename" => filename}, socket) do
    send_update(Artifacts.PanelComponent,
      id: "artifacts-panel",
      action: {:view, filename}
    )

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:manager, _, _, _} = msg, socket) do
    send_update(OmniUI.SessionsComponent, id: "sessions", manager_event: msg)
    {:noreply, socket}
  end

  def handle_info({OmniUI, :active_session_deleted}, socket) do
    {:noreply, push_patch(socket, to: "/")}
  end

  @impl OmniUI
  def agent_event(:tool_result, %{name: name}, socket) when name in ["artifacts", "repl"] do
    send_update(Artifacts.PanelComponent, id: "artifacts-panel", action: :rescan)
    socket
  end

  def agent_event(_event, _data, socket), do: socket

  defp save_title(pid, ""), do: save_title(pid, nil)
  defp save_title(pid, title) when is_pid(pid), do: Omni.Session.set_title(pid, title)
  defp save_title(_pid, _raw), do: :ok
end
