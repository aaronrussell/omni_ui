defmodule OmniUI.AgentInterface do
  use Phoenix.LiveComponent
  import OmniUI.Messages

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-background text-foreground">
      <!-- Messages Area -->
      <div class="flex-1 overflow-y-auto">
        <div class="max-w-3xl mx-auto p-4 pb-0">
          <div class="flex flex-col gap-3">
            <.message_list messages={@messages} />
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

  def mount(socket) do
	  {:ok, assign(socket,
			messages: [
			  Omni.message("Hello"),
				Omni.message(role: :assistant, content: "Hi how are you")
			]
		)}
  end
end
