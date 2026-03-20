defmodule OmniUI.MessageEditor do
  use Phoenix.LiveComponent
  alias OmniUI.Icons

  slot :control do
    attr :class, :string
  end

  def render(assigns) do
    ~H"""
    <div class={[
      "w-full border rounded-xl overflow-hidden shadow-xl",
      "bg-omni-bg border-omni-border-1/75 [&:has(textarea:focus)]:border-omni-accent-1"
    ]}>
      <!-- TODO dragging effect -->
      <!-- TODO attachments -->

      <form phx-submit="submit" phx-change="change" phx-target={@myself}>
        <div class="relative">
          <textarea
            name="input"
            class={[
              "block w-full max-h-64 p-4 pr-16 outline-none overflow-y-auto",
              "field-sizing-content resize-none",
              "bg-transparent text-omni-text-3 focus:text-omni-text-1 placeholder-omni-text-4"
              ]}
            placeholder="Type your message here..."
            rows="1">{@input}</textarea>
          <div class="absolute top-0 right-0 bottom-0 p-4 flex items-center justify-center">
            <button
              type="submit"
              class={[
                "transition-colors cursor-pointer",
                "text-omni-text-4 hover:text-omni-accent-1"
              ]}>
              <Icons.send class="size-6" />
            </button>
          </div>
        </div>

        <div class={[
          "flex items-center gap-4 h-14 p-4 border-t",
          "bg-omni-bg-1 border-omni-border-2"
        ]}>
          <button class={[
            "flex items-center gap-1.5 text-sm transition-colors cursor-pointer",
            "text-omni-text-1 hover:text-omni-accent-1"
          ]}>
            <Icons.paperclip class="size-4" />
            <span>Attach</span>
          </button>

          <%= for control <- @control do %>
            <div class={[
              "before:content=[''] before:w-px before:h-3 before:bg-omni-border-3",
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
