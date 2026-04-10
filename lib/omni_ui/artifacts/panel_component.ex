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
    * `action: {:view, filename}` — opens the named artifact in the panel
      (e.g. when the user clicks an inline artifact tool-use button)

  ## View modes

  The active artifact's MIME type determines its default view mode. A separate
  `view_source` boolean can override the default to `:source` for toggleable types.

    * `:iframe` — (`text/html`, `application/pdf`) served from the artifact
      Plug route; HTML gets `sandbox="allow-scripts"`
    * `:markdown` — (`text/markdown`) MDEx-rendered HTML with typography styles
    * `:media` — (`image/*`) centered `<img>` tag served from the Plug route
    * `:source` — (`text/*`, `application/json`, and other text-like types)
      syntax-highlighted source via Lumis
    * `:download` — (everything else) download link

  HTML, Markdown, and SVG artifacts support a **Preview / Code toggle** in the
  artifact bar, switching between the default view and `:source`.
  """

  use Phoenix.LiveComponent

  import OmniUI.Artifacts.PanelUI
  import OmniUI.Helpers, only: [highlight_code: 2, md_styles: 0, to_md: 1]

  alias OmniUI.Artifacts.{FileSystem, URL}

  @iframe_mime_types ~w(
    text/html application/pdf
  )

  @text_like_types ~w(
    application/json application/javascript application/xml
    application/x-yaml application/x-sh application/sql
  )

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class={["omni-ui h-full flex flex-col bg-omni-bg" | md_styles()]}>
      <.artifact_bar
        artifact={@artifacts[@active_artifact]}
        view_source={@view_source}
        token={@token}
        target={@myself} />

      <div class="flex-1 overflow-auto">
        <%= if @active_artifact do %>
          <.artifact_view
            artifact={@artifacts[@active_artifact]}
            content={@content}
            view={@view}
            token={@token}
            target={@myself} />
        <% else %>
          <.artifact_list artifacts={@artifacts} target={@myself} />
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       artifacts: %{},
       active_artifact: nil,
       content: nil,
       # :iframe, :markdown, :media, :source, :download
       view: nil,
       view_source: false,
       session_id: nil,
       token: nil
     )}
  end

  @impl true
  def update(%{action: :rescan}, socket) do
    artifacts = scan_artifacts(socket.assigns.session_id)

    case Map.get(artifacts, socket.assigns.active_artifact) do
      nil ->
        {:ok, assign(socket, artifacts: artifacts, active_artifact: nil)}

      _ ->
        {:ok, assign(socket, :artifacts, artifacts)}
    end
  end

  def update(%{action: {:view, filename}}, socket) do
    # TODO: Stale view action — the artifact may have been deleted since the
    # chat message containing the button was rendered. Currently silent
    # no-op to avoid crashing. Should show an error banner / notice in the
    # panel explaining the artifact has been deleted. See advanced_tooling.md
    # Phase 8.
    if Map.has_key?(socket.assigns.artifacts, filename) do
      socket =
        socket
        |> assign(active_artifact: filename, view_source: false)
        |> assign_content()

      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  def update(%{session_id: new_session_id} = assigns, socket) do
    old_session_id = socket.assigns.session_id
    socket = assign(socket, assigns)

    if new_session_id != old_session_id and new_session_id != nil do
      {:ok,
       assign(socket,
         artifacts: scan_artifacts(new_session_id),
         active_artifact: nil,
         content: nil,
         view: nil,
         view_source: false,
         token: URL.sign_token(socket, new_session_id)
       )}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("select_artifact", %{"filename" => filename}, socket) do
    socket =
      socket
      |> assign(active_artifact: filename, view_source: false)
      |> assign_content()

    {:noreply, socket}
  end

  def handle_event("toggle_view", _, socket) do
    socket =
      socket
      |> assign(view_source: !socket.assigns.view_source)
      |> assign_content()

    {:noreply, socket}
  end

  def handle_event("close_artifact", _, socket) do
    {:noreply,
     assign(socket,
       active_artifact: nil,
       content: nil,
       view: nil,
       view_source: false
     )}
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp assign_content(socket) do
    artifact = socket.assigns.artifacts[socket.assigns.active_artifact]

    view =
      case socket.assigns.view_source do
        true -> :source
        _ -> view_mode(artifact.mime_type)
      end

    assign(socket,
      content: load_content(view, artifact, socket.assigns.session_id),
      view: view
    )
  end

  # :iframe, :markdown, :media, :source, :download

  defp view_mode(mime_type) when mime_type in @iframe_mime_types, do: :iframe
  defp view_mode("text/markdown"), do: :markdown
  defp view_mode(mime_type) when mime_type in @text_like_types, do: :source

  defp view_mode(mime_type) do
    cond do
      String.starts_with?(mime_type, "image/") -> :media
      String.starts_with?(mime_type, "text/") -> :source
      true -> :download
    end
  end

  defp load_content(:markdown, artifact, session_id) do
    {:ok, data} = FileSystem.read(artifact.filename, session_id: session_id)
    to_md(data)
  end

  defp load_content(:source, artifact, session_id) do
    {:ok, code} = FileSystem.read(artifact.filename, session_id: session_id)
    highlight_code(code, artifact.filename)
  end

  defp load_content(_view, _artifact, _session_id), do: nil

  defp scan_artifacts(session_id) do
    {:ok, artifacts} = FileSystem.list(session_id: session_id)
    Map.new(artifacts, &{&1.filename, &1})
  end
end
