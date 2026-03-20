defmodule OmniUI.MessageEditor do
  use Phoenix.LiveComponent
  alias OmniUI.Icons

  slot :control do
    attr :class, :string
  end

  def render(assigns) do
    ~H"""
    <div class={[
      "w-full bg-white border border-slate-400/75 rounded-xl overflow-hidden shadow-xl",
      "[&:has(textarea:focus)]:border-blue-500"
    ]}>
      <!-- TODO dragging effect -->
      <!-- TODO attachments -->

      <form phx-submit="submit" phx-change="change" phx-target={@myself}>
        <div class="relative">
          <textarea
            name="input"
            class={[
              "block w-full max-h-64 p-4 pr-16 text-foreground outline-none field-sizing-content resize-none overflow-y-auto",
              "bg-transparent text-slate-500 focus:text-slate-700 placeholder-slate-400"
              ]}
            placeholder="Type your message here..."
            rows="1">{@input}</textarea>
          <div class="absolute top-0 right-0 bottom-0 p-4 flex items-center justify-center">
            <button type="submit" class="text-slate-400 hover:text-blue-500 transition-colors cursor-pointer">
              <Icons.send class="size-6" />
            </button>
          </div>
        </div>

        <div class="flex items-center gap-4 h-14 p-4 bg-slate-100 border-t border-slate-300">
          <button class={[
            "flex items-center gap-1.5 text-sm transition-colors cursor-pointer",
            "text-slate-700 hover:text-blue-600"
          ]}>
            <Icons.paperclip class="size-4" />
            <span>Attach</span>
          </button>

          <%= for control <- @control do %>
            <div class={[
              "before:content=[''] before:w-px before:h-3 before:bg-slate-300",
              control.class
            ]}>
              {render_slot(control)}
            </div>
          <% end %>


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
