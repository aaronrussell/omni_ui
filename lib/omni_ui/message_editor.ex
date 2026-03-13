defmodule OmniUI.MessageEditor do
  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
    <div class="bg-card rounded-xl border shadow-sm relative -- border-border">
      <!-- TODO dragging effect -->
      <!-- TODO attachments -->

      <form phx-submit="submit" phx-change="change" phx-target={@myself}>
        <textarea
          name="input"
          class="w-full bg-transparent p-4 text-foreground placeholder-muted-foreground outline-none resize-none overflow-y-auto"
          rows="1"
          style="max-height: 200px; field-sizing: content; min-height: 1lh; height: auto;"
        >{@input}</textarea>

        <div class="px-2 pb-2 flex items-center justify-between">
          <div class="flex gap-2 items-center">
            <!-- TODO attachment button -->
            <!-- TODO thinking select -->
          </div>

          <div class="flex gap-2 items-center">
            <!-- TODO model select -->
            <button type="submit" class="h-8">
              Send
            </button>
          </div>
        </div>
      </form>
    </div>
    """
  end

  def mount(socket) do
    {:ok, assign(socket, input: "")}
  end

  def handle_event("change", %{"input" => input}, socket) do
    {:noreply, assign(socket, input: input)}
  end

  def handle_event("submit", _, socket) do
    input = String.trim(socket.assigns.input)

    if input == "" do
      {:noreply, socket}
    else
      send(self(), {:new_message, Omni.message(input)})
      {:noreply, assign(socket, input: "")}
    end
  end
end
