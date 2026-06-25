defmodule Omni.UI.TurnComponent do
  @moduledoc """
  A LiveComponent that renders a completed conversation turn.

  Displays the user message and assistant response for a single `Omni.UI.Turn`,
  with support for:

    * **Inline editing** — the user can edit their message, which sends
      `{Omni.UI, :edit_message, turn_id, Omni.Message.t()}` to the parent LiveView
      to create a new conversation branch.
    * **Branch navigation** — when a turn has multiple edits or regenerations,
      version navigation arrows are shown (delegated to `version_nav` in
      `Omni.UI.CoreUI`).
    * **Copy to clipboard** — pushes an `"omni:clipboard"` event to the client
      with the text content for a given role.

  ## Events

  Events handled locally:

    * `"edit"` — enters edit mode, populating the textarea with current text.
    * `"cancel"` — exits edit mode.
    * `"change"` — tracks textarea input.
    * `"copy"` — pushes clipboard event to client.

  Events forwarded to parent via `send/2`:

    * `"submit"` — sends `{Omni.UI, :edit_message, turn_id, message}` to parent.

  Events forwarded to parent via `phx-click` (no component handling):

    * `"omni:navigate"` — branch navigation, handled by parent's `handle_event`.
    * `"omni:regenerate"` — response regeneration, handled by parent's `handle_event`.
  """

  use Phoenix.LiveComponent
  import Omni.UI.ChatUI
  alias Phoenix.LiveView.JS

  attr :turn, Omni.UI.Turn, required: true
  attr :tool_components, :map, default: %{}

  slot :user, doc: "custom user slot; forwarded to turn/1 unless editing"
  slot :assistant, doc: "custom assistant slot; forwarded to turn/1"

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.turn turn={@turn} tool_components={@tool_components} target={@myself}>
        <:user :if={@editing} :let={_turn}>
          <.user_edit_form turn_id={@turn.id} input={@input} target={@myself} />
        </:user>
        <:user :if={not @editing} :for={item <- @user} :let={turn}>
          {render_slot(item, turn)}
        </:user>

        <:assistant :for={item <- @assistant} :let={turn}>
          {render_slot(item, turn)}
        </:assistant>
      </.turn>
    </div>
    """
  end

  # Inline edit form — extracted as a function component for readability,
  # not for reuse. Lives here rather than in a *UI module because it's
  # tightly coupled to this component's event handling.
  attr :turn_id, :integer, required: true
  attr :input, :string, required: true
  attr :target, :any, required: true

  defp user_edit_form(assigns) do
    ~H"""
    <div
      class={[
        "w-full border rounded-xl",
        "bg-omni-bg border-omni-border-1/75 [&:has(textarea:focus)]:border-omni-accent-1",
      ]}>
      <form
        id={"turn-#{@turn_id}-form"}
        phx-submit={JS.dispatch("omni:before-update") |> JS.push("submit")}
        phx-change="change"
        phx-target={@target}>
        <div class="relative">
          <textarea
            id={"turn-#{@turn_id}-input"}
            name="input"
            phx-hook="Omni.UI.ChatUI.SubmitOnEnter"
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
              <Lucideicons.send class="size-5 [:disabled>&]:hidden" />
              <Lucideicons.sparkle class="hidden size-4 text-amber-400 animate-spin [:disabled>&]:block" />
            </button>
          </div>
        </div>

        <div class="bg-omni-bg-1 border-t border-omni-border-2 rounded-b-xl">
          <div class="flex items-center gap-4 h-14 p-4">
            <div class="flex-auto flex gap-2 pr-2 text-omni-text-3">
              <Lucideicons.info class="size-4" />
              <p class="text-xs">
                Editing this message will create a new, navigable conversation branch.
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
    {:ok, assign(socket, editing: false, input: "", tool_components: %{})}
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

  def handle_event("copy", %{"role" => role}, socket) do
    text = Omni.UI.Turn.get_text(socket.assigns.turn, String.to_existing_atom(role))
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
      send(self(), {Omni.UI, :edit_message, socket.assigns.turn.id, message})
      {:noreply, assign(socket, editing: false, input: "")}
    end
  end
end
