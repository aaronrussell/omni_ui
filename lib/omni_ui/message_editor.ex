defmodule OmniUI.MessageEditor do
  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
    <div class="bg-card rounded-xl border shadow-sm relative -- border-border">
      <!-- TODO dragging effect -->
      <!-- TODO attachments -->

      <textarea
        class="w-full bg-transparent p-4 text-foreground placeholder-muted-foreground outline-none resize-none overflow-y-auto"
        rows="1"
        style="max-height: 200px; field-sizing: content; min-height: 1lh; height: auto;"
      ></textarea>

      <div class="px-2 pb-2 flex items-center justify-between">
        <div class="flex gap-2 items-center">
          <!-- TODO attachment button -->
          <!-- TODO thinking select -->
        </div>

        <div class="flex gap-2 items-center">
          <!-- TODO model select -->
          <button class="h-8">
            Send
          </button>
        </div>
      </div>
    </div>
    """
  end

  def mount(socket) do
	  {:ok, socket}
  end

end
