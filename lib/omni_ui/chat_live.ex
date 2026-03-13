defmodule OmniUI.ChatLive do
  use Phoenix.LiveView
  import OmniUI.Messages

  require Logger

  def render(assigns) do
     ~H"""
     <div class="relative w-full h-full overflow-hidden flex">
       <div class="h-full w-full">
         <.agent_interface messages={@context.messages} />
       </div>

       <!-- TODO : artifacts button -->

       <div class="h-full hidden">
         <!-- TODO : artifacts panel -->
       </div>
     </div>
     """
  end

  def agent_interface(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-background text-foreground">
      <!-- Messages Area -->
      <div class="flex-1 overflow-y-auto">
        <div class="max-w-3xl mx-auto p-4 pb-0">
          <div class="flex flex-col gap-3">
            <.message
              :for={message <- @messages}
              message={message}
              tool_results={tool_result_map(message, @messages)}
            />
            <!-- TODO streaming message -->
          </div>
        </div>
      </div>

      <div class="shrink-0">
        <div class="max-w-3xl mx-auto px-2">
          <.live_component module={OmniUI.MessageEditor} id="editor" />
          <!-- TODO usage stats -->
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, agent} = Omni.Agent.start_link(model: {:opencode, "kimi-k2.5"})

    {:ok, assign(socket,
      agent: agent,
      context: Omni.context(messages: [])
    )}
  end

  def handle_info({:new_message, message}, socket) do
    context = Omni.Context.push(socket.assigns.context, message)
    :ok = Omni.Agent.prompt(socket.assigns.agent, message.content)
    {:noreply, assign(socket, context: context)}
  end

  def handle_info({:agent, _pid, :done, response}, socket) do
    context = Omni.Context.push(socket.assigns.context, response)
    {:noreply, assign(socket, context: context)}
  end

  def handle_info({:agent, _pid, :error, reason}, socket) do
    Logger.error("Agent error: #{inspect(reason)}")
    {:noreply, put_flash(socket, :error, "Something went wrong")}
  end

  # Catch-all
  def handle_info({:agent, _pid, _stop_reason, _msg}, socket) do
    {:noreply, socket}
  end

  # TODO - build tool result map
  defp tool_result_map(_message, _messages) do
    %{}
  end
end
