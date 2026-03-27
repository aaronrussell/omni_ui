defmodule OmniUI.UserMessage do
  use Phoenix.LiveComponent
  import OmniUI.Components

  alias Phoenix.LiveView.JS

  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-end gap-6">
      <%= if @editing do %>
        <div
          class={[
            "w-full border rounded-xl",
            "bg-omni-bg border-omni-border-1/75 [&:has(textarea:focus)]:border-omni-accent-1",
          ]}
        >
          <form phx-change="change" phx-submit="submit" phx-target={@myself}>
            <div class="relative">
              <textarea
                name="input"
                class={[
                  "block w-full max-h-64 p-4 pr-16 outline-none overflow-y-auto",
                  "field-sizing-content resize-none",
                  "bg-transparent text-omni-text-3 focus:text-omni-text-1 placeholder-omni-text-4"
                ]}
                rows="1"
                phx-mounted={JS.dispatch("omni:focus")}>{@input}</textarea>

              <div class="absolute top-0 right-0 bottom-0 p-4 flex items-center justify-center">
                <button
                  type="submit"
                  class={[
                    "transition-colors cursor-pointer",
                    "text-omni-text-3 hover:text-omni-accent-1"
                  ]}>
                  <Lucideicons.send class="size-6 [:disabled>&]:hidden" />
                  <Lucideicons.sparkle class="hidden size-5 text-amber-400 animate-spin [:disabled>&]:block" />
                </button>
              </div>
            </div>

            <div class="bg-omni-bg-1 border-t border-omni-border-2 rounded-b-xl">
              <div class="flex items-center gap-4 h-14 p-4">
                <div class="flex-auto flex gap-2 pr-2 text-omni-text-3">
                  <Lucideicons.info class="size-4" />
                  <p class="text-xs">
                    Editing this message will create a new conversation branch. You can switch between branches using the arrow navigation buttons.
                  </p>
                </div>

                <button
                  type="button"
                  phx-click="cancel"
                  phx-target={@myself}
                  class={[
                    "flex items-center gap-1.5 text-sm transition-colors cursor-pointer",
                    "text-omni-text-2 hover:text-omni-accent-1"
                  ]}>
                  <Lucideicons.x class="size-4" />
                  <span>Cancel</span>
                </button>
              </div>
            </div>
          </form>
        </div>
      <% else %>
        <.user_message text={@text} attachments={@attachments} />

        <.user_message_actions
          turn_id={@turn_id}
          versions={@versions}
          status={@status}
          timestamp={@timestamp}
          on_edit={JS.push("edit", target: @myself)} />
      <% end %>
    </div>
    """
  end

  def mount(socket) do
    {:ok, assign(socket, editing: false, input: "")}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def handle_event("edit", _, socket) do
    input =
      socket.assigns.text
      |> Enum.map(& &1.text)
      |> Enum.join("\n\n")

    {:noreply, assign(socket, editing: true, input: input)}
  end

  def handle_event("cancel", _, socket) do
    {:noreply, assign(socket, editing: false, input: "")}
  end

  def handle_event("change", %{"input" => input}, socket) do
    {:noreply, assign(socket, input: input)}
  end

  def handle_event("submit", _, socket) do
    # Phase 2 — will send edit to parent LiveView
    {:noreply, socket}
  end
end
