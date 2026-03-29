defmodule OmniUI.EditorComponent do
  @moduledoc """
  A LiveComponent for composing and submitting user messages.

  Provides a textarea for text input, file attachment via click-to-attach and
  drag-and-drop, and a submit button. On submit, builds an `Omni.Message` with
  text and base64-encoded attachments, then sends it to the parent LiveView as
  `{OmniUI, :new_message, Omni.Message.t()}` via `send/2`.

  ## Upload constraints

    * Accepted types: `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.pdf`
    * Max entries: 10
    * Max file size: 20 MB

  ## Slots

    * `:toolbar` — optional slot rendered in the bottom bar alongside the
      attach button. Used by `AgentLive` for model/thinking selectors.
  """

  use Phoenix.LiveComponent
  import OmniUI.Components

  slot :toolbar

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class={[
        "w-full border rounded-xl shadow-xl",
        "bg-omni-bg border-omni-border-1/75 [&:has(textarea:focus)]:border-omni-accent-1",
        "[&.phx-drop-target-active]:border-omni-accent-1 [&.phx-drop-target-active]:ring-2 [&.phx-drop-target-active]:ring-omni-accent-1/50"
      ]}
      phx-drop-target={@uploads.attachments.ref}
      >
      <form phx-submit="submit" phx-change="change" phx-target={@myself}>
        <div class="relative">
          <div
            class={[
              "absolute inset-0 z-10 bg-omni-bg-2 pointer-events-none items-center justify-center rounded-t-xl",
              "hidden [.phx-drop-target-active_&]:flex"
            ]}>
            <span class="text-sm text-omni-text-3">Drop files here</span>
          </div>

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
                "text-omni-text-3 hover:text-omni-accent-1"
              ]}>
              <Lucideicons.send class="size-6 [:disabled>&]:hidden" />
              <Lucideicons.sparkle class="hidden size-5 text-amber-400 animate-spin [:disabled>&]:block" />
            </button>
          </div>
        </div>

        <div class="bg-omni-bg-1 border-t border-omni-border-2 rounded-b-xl">
          <div
            :if={@uploads.attachments.entries != []}
            class="flex flex-wrap items-center gap-3 px-4 pt-3">
            <.attachment
              :for={entry <- @uploads.attachments.entries}
              name={entry.client_name}
              media_type={entry.client_type}>

              <:image :if={match?("image/" <> _, entry.client_type)}>
                <.live_img_preview entry={entry} />
              </:image>

              <:action>
                <button
                  type="button"
                  phx-click="cancel-upload"
                  phx-value-ref={entry.ref}
                  phx-target={@myself}
                  class={[
                    "absolute -top-1 -right-1 size-5 rounded-full flex items-center justify-center transition-all cursor-pointer",
                    "[@media(hover:hover)]:opacity-0 group-hover:opacity-100",
                    "bg-omni-bg text-omni-text-4 border border-omni-border-2 hover:text-red-500 hover:border-red-500",
                  ]}>
                  <Lucideicons.x class="size-3" />
                </button>
              </:action>

            </.attachment>
          </div>

          <div class="flex items-center gap-4 h-14 p-4">
            <label class={[
              "flex items-center gap-1.5 text-sm transition-colors cursor-pointer",
              "text-omni-text-1 hover:text-omni-accent-1"
            ]}>
              <Lucideicons.paperclip class="size-4" />
              <span>Attach</span>
              <.live_file_input upload={@uploads.attachments} class="hidden" />
            </label>

            {render_slot(@toolbar)}
          </div>
        </div>
      </form>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    socket =
      socket
      |> assign(input: "")
      |> allow_upload(:attachments,
        accept: ~w(.jpg .jpeg .png .gif .webp .pdf),
        max_entries: 10,
        max_file_size: 20_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("change", %{"input" => input}, socket) do
    {:noreply, assign(socket, input: input)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachments, ref)}
  end

  def handle_event("submit", _, socket) do
    input = String.trim(socket.assigns.input)

    attachments =
      consume_uploaded_entries(socket, :attachments, fn %{path: path}, entry ->
        data = path |> File.read!() |> Base.encode64()

        {:ok,
         %Omni.Content.Attachment{
           source: {:base64, data},
           media_type: entry.client_type
         }}
      end)

    content =
      if(input != "", do: [%Omni.Content.Text{text: input}], else: []) ++ attachments

    if content == [] do
      {:noreply, socket}
    else
      send(self(), {OmniUI, :new_message, Omni.message(role: :user, content: content)})
      {:noreply, assign(socket, input: "")}
    end
  end
end
