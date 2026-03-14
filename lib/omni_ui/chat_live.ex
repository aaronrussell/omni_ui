defmodule OmniUI.ChatLive do
  use Phoenix.LiveView
  import OmniUI.Messages
  import OmniUI.Helpers, only: [format_usage: 1]

  require Logger

  attr :messages, :list, required: true
  attr :streaming, :boolean, required: true
  attr :streaming_message, :map, required: true
  attr :usage, Omni.Usage, required: true

  def render(assigns) do
    ~H"""
    <div class="relative w-full h-full overflow-hidden flex">
      <div class="h-full w-full">
        <.agent_interface
          messages={@messages}
          streaming={@streaming}
          streaming_message={@streaming_message}
          usage={@usage}
        />
      </div>

      <!-- TODO : artifacts button -->

      <div class="h-full hidden">
        <!-- TODO : artifacts panel -->
      </div>
    </div>
    """
  end

  attr :messages, :list, required: true
  attr :streaming, :boolean, required: true
  attr :streaming_message, :map, required: true
  attr :usage, Omni.Usage, required: true

  def agent_interface(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-background text-foreground">
      <!-- Messages Area -->
      <div class="flex-1 overflow-y-auto">
        <div class="max-w-3xl mx-auto p-4 pb-0">
          <div class="flex flex-col gap-3">
            <.message
              :for={message <- @messages}
              {message}
            />
            <.message
              :if={@streaming}
              streaming={@streaming}
              {@streaming_message}
            />
          </div>
        </div>
      </div>

      <div class="shrink-0">
        <div class="max-w-3xl mx-auto px-2">
          <.live_component module={OmniUI.MessageEditor} id="editor" />
          <div class="text-xs text-muted-foreground flex justify-between items-center h-5">
            <div class="flex items-center gap-1">
              <!-- MAYBE - theme togggle?? -->
            </div>
            <div class="flex ml-auto items-center gap-3">
              <span><%= format_usage(@usage) %></span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, agent} = Omni.Agent.start_link(
      model: {:anthropic, "claude-haiku-4-5"},
      system: "Always look up the current user details before responding to the first message.",
      tools: [
        Omni.tool(
          name: "current_user",
          description: "Lookup the current user details",
          input_schema: Omni.Schema.object([]),
          handler: fn _ -> %{name: "John Smith", location: "London, UK"} end
        )
      ]
    )

    socket =
      assign(socket,
        agent: agent,
        messages: [],
        streaming: false,
        streaming_message: nil,
        usage: Omni.Agent.get_state(agent, :usage)
      )

    {:ok, socket}
  end

  def handle_info({:new_message, message}, socket) do
    :ok = Omni.Agent.prompt(socket.assigns.agent, message.content, max_steps: 5)
    message = Map.take(message, [:role, :content, :timestamp])

    socket =
      assign(socket,
        messages: socket.assigns.messages ++ [message],
        streaming: true,
        streaming_message: %{
          role: :assistant,
          content: [],
          tool_results: %{},
          usage: nil,
          timestamp: DateTime.utc_now()
        }
      )

    {:noreply, socket}
  end

  def handle_info({:agent, _pid, :thinking_start, _data}, socket) do
    socket =
      update(socket, :streaming_message, fn msg ->
        %{msg | content: msg.content ++ [%Omni.Content.Thinking{text: ""}]}
      end)

    {:noreply, socket}
  end

  def handle_info({:agent, _pid, :text_start, _data}, socket) do
    socket =
      update(socket, :streaming_message, fn msg ->
        %{msg | content: msg.content ++ [%Omni.Content.Text{text: ""}]}
      end)

    {:noreply, socket}
  end

  def handle_info({:agent, _pid, delta_type, %{delta: delta}}, socket)
      when delta_type in [:thinking_delta, :text_delta] do
    socket =
      update(socket, :streaming_message, fn msg ->
        content = List.update_at(msg.content, -1, &%{&1 | text: &1.text <> delta})
        %{msg | content: content}
      end)

    {:noreply, socket}
  end

  def handle_info({:agent, _pid, :tool_use_end, %{content: tool_use}}, socket) do
    socket =
      update(socket, :streaming_message, fn msg ->
        %{msg | content: msg.content ++ [tool_use]}
      end)

    dbg {:tool_use, tool_use}

    {:noreply, socket}
  end

  def handle_info({:agent, _pid, :tool_result, tool_result}, socket) do
    socket =
      update(socket, :streaming_message, fn msg ->
        tool_results = Map.put(msg.tool_results, tool_result.tool_use_id, tool_result)
        %{msg | tool_results: tool_results}
      end)

    dbg {:tool_result, tool_result}

    {:noreply, socket}
  end

  def handle_info({:agent, _pid, :done, response}, socket) do
    completed = %{
      socket.assigns.streaming_message
      | usage: response.usage,
        timestamp: response.message.timestamp
    }

    socket =
      assign(socket,
        messages: socket.assigns.messages ++ [completed],
        streaming: false,
        streaming_message: nil,
        usage: Omni.Agent.get_state(socket.assigns.agent, :usage)
      )

    {:noreply, socket}
  end

  def handle_info({:agent, _pid, :error, reason}, socket) do
    Logger.error("Agent error: #{inspect(reason)}")

    socket =
      socket
      |> assign(streaming: false, streaming_message: nil)
      |> put_flash(:error, "Something went wrong")

    {:noreply, socket}
  end

  # Catch-all
  def handle_info({:agent, _pid, _type, _data}, socket) do
    {:noreply, socket}
  end
end
