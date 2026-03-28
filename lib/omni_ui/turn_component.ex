defmodule OmniUI.TurnComponent do
  @moduledoc """
  A LiveComponent that renders a completed conversation turn.

  Displays the user message and assistant response for a single `OmniUI.Turn`,
  with support for:

    * **Inline editing** — the user can edit their message, which sends
      `{:edit_message, turn_id, Omni.Message.t()}` to the parent LiveView
      to create a new conversation branch.
    * **Branch navigation** — when a turn has multiple edits or regenerations,
      version navigation arrows are shown (delegated to `version_nav` in
      `OmniUI.Components`).
    * **Copy to clipboard** — pushes an `"omni:clipboard"` event to the client
      with the text content for a given role.

  ## Events

  Events handled locally:

    * `"edit"` — enters edit mode, populating the textarea with current text.
    * `"cancel"` — exits edit mode.
    * `"change"` — tracks textarea input.
    * `"copy_message"` — pushes clipboard event to client.

  Events forwarded to parent via `send/2`:

    * `"submit"` — sends `{:edit_message, turn_id, message}` to parent.

  Events forwarded to parent via `phx-click` (no component handling):

    * `"navigate"` — branch navigation, handled by parent's `handle_event`.
    * `"regenerate"` — response regeneration, handled by parent's `handle_event`.
  """

  use Phoenix.LiveComponent
  import OmniUI.Components
  alias Phoenix.LiveView.JS

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.turn>
        <:user>
          <%= if @editing do %>
            <.user_edit_form input={@input} target={@myself} />
          <% else %>
            <.user_message text={@turn.user_text} attachments={@turn.user_attachments} />

            <.user_message_actions
              turn_id={@turn.id}
              versions={@turn.edits}
              timestamp={@turn.user_timestamp}
              target={@myself} />
          <% end %>
        </:user>

        <:assistant>
          <.assistant_message
            content={@turn.content}
            tool_results={@turn.tool_results}
            streaming={@turn.status == :streaming} />

          <.assistant_message_actions
            :if={@turn.status == :complete}
            turn_id={@turn.id}
            node_id={@turn.res_id}
            versions={@turn.regens}
            usage={@turn.usage}
            target={@myself} />
        </:assistant>
      </.turn>
    </div>
    """
  end

  # Inline edit form — extracted as a function component for readability,
  # not for reuse. Lives here rather than in OmniUI.Components because it's
  # tightly coupled to this component's event handling.
  attr :input, :string, required: true
  attr :target, :any, required: true

  defp user_edit_form(assigns) do
    ~H"""
    <div
      class={[
        "w-full border rounded-xl",
        "bg-omni-bg border-omni-border-1/75 [&:has(textarea:focus)]:border-omni-accent-1",
      ]}>
      <form phx-change="change" phx-submit={JS.dispatch("omni:before-update") |> JS.push("submit")} phx-target={@target}>
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
              phx-target={@target}
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
    """
  end

  @impl true
  def mount(socket) do
    {:ok, assign(socket, editing: false, input: "")}
  end

  # Local events

  @impl true
  def handle_event("edit", _, socket) do
    input =
      socket.assigns.turn.user_text
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

  def handle_event("copy_message", %{"role" => role}, socket) do
    text = OmniUI.Turn.get_text(socket.assigns.turn, String.to_existing_atom(role))
    {:noreply, push_event(socket, "omni:clipboard", %{text: text})}
  end

  # Forwarded to parent

  def handle_event("submit", _, socket) do
    input = String.trim(socket.assigns.input)

    if input == "" do
      {:noreply, socket}
    else
      content = [%Omni.Content.Text{text: input}]
      message = Omni.message(role: :user, content: content)
      send(self(), {:edit_message, socket.assigns.turn.id, message})
      {:noreply, assign(socket, editing: false, input: "")}
    end
  end
end
