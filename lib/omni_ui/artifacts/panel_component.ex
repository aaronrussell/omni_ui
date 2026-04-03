defmodule OmniUI.Artifacts.PanelComponent do
  @moduledoc """
  A LiveComponent that renders the artifacts panel.

  Receives `session_id` from the parent LiveView and manages all artifact
  state internally: the artifact index, active selection, content loading,
  and token signing.

  ## Assigns from parent

    * `session_id` — the current session ID (triggers rescan on change)

  ## Actions via `send_update`

    * `action: :rescan` — rescans the artifacts directory (e.g. after a
      tool result creates or modifies an artifact)

  ## Rendering modes

    * **Preview** (`text/html`, `image/svg+xml`) — iframe loading from the
      artifact Plug route with `sandbox="allow-scripts"`
    * **View** (`text/*`, `application/json`) — syntax-highlighted code via
      Lumis with inline styles
    * **Download** (everything else) — download link, with inline image
      preview for `image/*` types
  """

  use Phoenix.LiveComponent

  alias OmniUI.Artifacts.{FileSystem, URL}

  # ── Lifecycle ────────────────────────────────────────────────────

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       artifacts: %{},
       active_artifact: nil,
       content: nil,
       token: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    old_session_id = socket.assigns[:session_id]
    socket = assign(socket, Map.delete(assigns, :action))
    new_session_id = socket.assigns.session_id

    cond do
      # Session changed — full reset
      new_session_id != old_session_id and new_session_id != nil ->
        {:ok,
         socket
         |> assign(artifacts: scan(new_session_id), active_artifact: nil, content: nil)
         |> assign_token()}

      # Artifacts changed on disk — rescan
      assigns[:action] == :rescan ->
        artifacts = scan(new_session_id)
        socket = assign(socket, :artifacts, artifacts)

        if socket.assigns.active_artifact &&
             !Map.has_key?(artifacts, socket.assigns.active_artifact) do
          {:ok, assign(socket, active_artifact: nil, content: nil)}
        else
          {:ok, socket}
        end

      true ->
        {:ok, socket}
    end
  end

  # ── Events ───────────────────────────────────────────────────────

  @impl true
  def handle_event("select_artifact", %{"filename" => filename}, socket) do
    artifact = socket.assigns.artifacts[filename]
    content = load_content(artifact, socket.assigns.session_id)
    {:noreply, assign(socket, active_artifact: filename, content: content)}
  end

  def handle_event("close_artifact", _, socket) do
    {:noreply, assign(socket, active_artifact: nil, content: nil)}
  end

  # ── Render ───────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="h-full flex flex-col bg-omni-bg">
      <.artifact_bar
        artifact={@artifacts[@active_artifact]}
        token={@token}
        target={@myself} />

      <%= if @active_artifact do %>
        <.artifact_viewer
          artifact={@artifacts[@active_artifact]}
          content={@content}
          token={@token}
          target={@myself} />
      <% else %>
        <.artifact_list artifacts={@artifacts} target={@myself} />
      <% end %>
    </div>
    """
  end

  defp artifact_bar(assigns) do
    ~H"""
    <div class="flex items-center gap-4 h-12 p-4 border-b border-omni-border-2">
      <Lucideicons.monitor class="size-4" />
      <div class="font-semibold text-omni-text">{if(@artifact, do: @artifact.filename, else: "All artifacts")}</div>

      <div
        :if={@artifact}
        class="flex-auto flex items-center gap-2 justify-end">
          <p>toggle</p> <!-- todo: view toggle -->
        <a
          class={[
            "flex items-center justify-center size-7 rounded transition-colors cursor-pointer",
            "text-omni-text-1 hover:text-omni-accent-1 hover:bg-omni-accent-2/10"
          ]}
          href={artifact_url(@token, @artifact.filename)}
          download={@artifact.filename}>
          <Lucideicons.download class="size-4" />
        </a>
        <button
          class={[
            "flex items-center justify-center size-7 rounded cursor-pointer",
            "text-omni-text-1 hover:text-omni-accent-1 hover:bg-omni-accent-2/10"
          ]}
          phx-click="close_artifact"
          phx-target={@target}>
          <Lucideicons.x class="size-4" />
        </button>
      </div>

    </div>
    """
  end

  # ── Index view ───────────────────────────────────────────────────

  defp artifact_list(assigns) do
    ~H"""
    <div class="h-full p-12 pb-16 overflow-y-auto">
      <%= if @artifacts == %{} do %>
        <div class="h-full flex items-center justify-center">
          <p class="text-sm text-omni-text-3 italic">No artifacts yet.</p>
        </div>
      <% else %>

        <div class="border-b border-omni-border-2">
          <div class="px-2 py-3 grid grid-cols-[50%_1fr_1fr] gap-x-4 text-sm font-medium text-omni-text">
            <div>Name</div>
            <div>Size</div>
            <div>Updated</div>
          </div>
        </div>

        <div
          :for={{filename, artifact} <- Enum.sort(@artifacts)}
          class="border-b border-omni-border-3">
          <div
            class={[
              "px-2 py-3 grid grid-cols-[50%_1fr_1fr] gap-x-4 text-sm text-omni-text-3 group cursor-pointer transition-colors",
              "hover:bg-omni-bg-2"
            ]}
            phx-click="select_artifact"
            phx-value-filename={filename}
            phx-target={@target}>
            <div class={[
              "flex items-center gap-2 transition-colors",
              "text-omni-text-1 group-hover:text-omni-accent-1"
            ]}>
              <Lucideicons.file_code class="size-4" />
              <span class="font-medium">{filename}</span>
            </div>
            <div>{format_size(artifact.size)}</div>
            <div>{Calendar.strftime(artifact.updated_at, "%d %b %Y, %I:%M%P")}</div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Detail view ──────────────────────────────────────────────────

  defp artifact_viewer(assigns) do
    assigns = assign(assigns, :mode, render_mode(assigns.artifact.mime_type))

    ~H"""
    <div class="h-full flex flex-col">
      <div class="flex-1 min-h-0">
        <.viewer_content mode={@mode} artifact={@artifact} content={@content} token={@token} />
      </div>
    </div>
    """
  end

  # ── Render modes ─────────────────────────────────────────────────

  defp viewer_content(%{mode: :preview} = assigns) do
    ~H"""
    <iframe
      src={artifact_url(@token, @artifact.filename)}
      sandbox="allow-scripts"
      class="w-full h-full border-0"
    />
    """
  end

  defp viewer_content(%{mode: :view} = assigns) do
    ~H"""
    <div
      class={[
        "h-full overflow-auto",
        "[&>pre]:h-full [&>pre]:p-12 [&>pre]:text-sm"
      ]}>
      {@content}
    </div>
    """
  end

  defp viewer_content(%{mode: :download} = assigns) do
    ~H"""
    <div class="h-full flex flex-col items-center justify-center gap-4 p-4">
      <img
        :if={String.starts_with?(@artifact.mime_type, "image/")}
        src={artifact_url(@token, @artifact.filename)}
        class="max-w-full max-h-64 object-contain rounded-lg"
      />
      <a
        href={artifact_url(@token, @artifact.filename)}
        download={@artifact.filename}
        class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-omni-accent-1 text-white font-medium hover:bg-omni-accent-2 transition-colors"
      >
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-5">
          <path d="M10.75 2.75a.75.75 0 0 0-1.5 0v8.614L6.295 8.235a.75.75 0 1 0-1.09 1.03l4.25 4.5a.75.75 0 0 0 1.09 0l4.25-4.5a.75.75 0 0 0-1.09-1.03l-2.955 3.129V2.75Z" />
          <path d="M3.5 12.75a.75.75 0 0 0-1.5 0v2.5A2.75 2.75 0 0 0 4.75 18h10.5A2.75 2.75 0 0 0 18 15.25v-2.5a.75.75 0 0 0-1.5 0v2.5c0 .69-.56 1.25-1.25 1.25H4.75c-.69 0-1.25-.56-1.25-1.25v-2.5Z" />
        </svg>
        Download {@artifact.filename}
      </a>
    </div>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp render_mode(mime_type) do
    cond do
      mime_type in ["text/html", "image/svg+xml"] -> :preview
      String.starts_with?(mime_type, "text/") or mime_type == "application/json" -> :view
      true -> :download
    end
  end

  defp load_content(artifact, session_id) do
    case render_mode(artifact.mime_type) do
      :view ->
        {:ok, raw} = FileSystem.read(artifact.filename, session_id: session_id)

        Lumis.highlight!(raw,
          language: artifact.filename,
          formatter: {:html_inline, theme: "catppuccin_macchiato"}
        )
        |> Phoenix.HTML.raw()

      _ ->
        nil
    end
  end

  defp scan(session_id) do
    {:ok, artifacts} = FileSystem.list(session_id: session_id)
    Map.new(artifacts, &{&1.filename, &1})
  end

  defp assign_token(socket) do
    token = URL.sign_token(socket.endpoint, socket.assigns.session_id)
    assign(socket, :token, token)
  end

  defp artifact_url(token, filename) do
    "#{url_prefix()}/#{token}/#{filename}"
  end

  defp url_prefix do
    Application.get_env(:omni_ui, OmniUI.Artifacts, [])
    |> Keyword.get(:url_prefix, "/omni_artifacts")
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"
end
