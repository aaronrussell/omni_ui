defmodule OmniUI.FilesComponent do
  @moduledoc """
  A LiveComponent that renders the files panel.

  Receives `session_id` from the parent LiveView and manages all file
  state internally: the file index, active selection, content loading,
  and token signing.

  ## Assigns from parent

    * `session_id` — the current session ID (triggers rescan on change)

  ## Actions via `send_update`

    * `action: :rescan` — rescans the files directory (e.g. after a
      tool result creates or modifies a file)
    * `action: {:view, filename}` — opens the named file in the panel
      (e.g. when the user clicks an inline file tool-use button)

  ## View modes

  The active file's MIME type determines its default view mode. A separate
  `view_source` boolean can override the default to `:source` for toggleable types.

    * `:iframe` — (`text/html`, `application/pdf`) served from the file
      Plug route; HTML gets `sandbox="allow-scripts"`
    * `:markdown` — (`text/markdown`) MDEx-rendered HTML with typography styles
    * `:media` — (`image/*`) centered `<img>` tag served from the Plug route
    * `:source` — (`text/*`, `application/json`, and other text-like types)
      syntax-highlighted source via Lumis
    * `:download` — (everything else) download link

  HTML, Markdown, and SVG files support a **Preview / Code toggle** in the
  file bar, switching between the default view and `:source`.
  """

  use Phoenix.LiveComponent

  import OmniUI.FilesUI
  import OmniUI.Helpers, only: [highlight_code: 2, md_styles: 0, to_md: 1]

  alias Omni.Tools.Files.FS
  alias OmniUI.Files.URL

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
    <section
      class="omni-ui h-full flex flex-col bg-omni-bg">
      <.file_bar
        file={@files[@active_file]}
        view_source={@view_source}
        token={@token}
        target={@myself} />

      <div class={["flex-1 overflow-auto" | md_styles()]}>
        <%= if @active_file do %>
          <.file_view
            file={@files[@active_file]}
            content={@content}
            view={@view}
            token={@token}
            target={@myself} />
        <% else %>
          <.file_list files={@files} error={@error} target={@myself} />
        <% end %>
      </div>
    </section>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       files: %{},
       active_file: nil,
       content: nil,
       error: nil,
       view: nil,
       view_source: false,
       session_id: nil,
       token: nil
     )}
  end

  @impl true
  def update(%{action: :rescan}, socket) do
    files = scan_files(socket.assigns.session_id)

    case Map.get(files, socket.assigns.active_file) do
      nil ->
        {:ok, assign(socket, files: files, active_file: nil, error: nil)}

      _ ->
        {:ok, assign(socket, files: files, error: nil)}
    end
  end

  def update(%{action: {:view, filename}}, socket) do
    if Map.has_key?(socket.assigns.files, filename) do
      socket =
        socket
        |> assign(active_file: filename, view_source: false, error: nil)
        |> assign_content()

      {:ok, socket}
    else
      {:ok, assign(socket, active_file: nil, error: "\"#{filename}\" has been deleted.")}
    end
  end

  def update(%{session_id: new_session_id} = assigns, socket) do
    old_session_id = socket.assigns.session_id
    socket = assign(socket, assigns)

    cond do
      new_session_id == old_session_id ->
        {:ok, socket}

      new_session_id == nil ->
        {:ok,
         assign(socket,
           files: %{},
           active_file: nil,
           content: nil,
           view: nil,
           view_source: false,
           token: nil
         )}

      true ->
        {:ok,
         assign(socket,
           files: scan_files(new_session_id),
           active_file: nil,
           content: nil,
           view: nil,
           view_source: false,
           token: URL.sign_token(socket, new_session_id)
         )}
    end
  end

  @impl true
  def handle_event("select_file", %{"filename" => filename}, socket) do
    socket =
      socket
      |> assign(active_file: filename, view_source: false, error: nil)
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

  def handle_event("close_file", _, socket) do
    {:noreply,
     assign(socket,
       active_file: nil,
       content: nil,
       view: nil,
       view_source: false
     )}
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp assign_content(socket) do
    file = socket.assigns.files[socket.assigns.active_file]

    view =
      case socket.assigns.view_source do
        true -> :source
        _ -> view_mode(file.media_type)
      end

    assign(socket,
      content: load_content(view, file, socket.assigns.session_id),
      view: view
    )
  end

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

  defp load_content(:markdown, file, session_id) do
    {:ok, data} = FS.read(session_fs(session_id), file.filename)
    to_md(data)
  end

  defp load_content(:source, file, session_id) do
    {:ok, code} = FS.read(session_fs(session_id), file.filename)
    highlight_code(code, file.filename)
  end

  defp load_content(_view, _file, _session_id), do: nil

  defp scan_files(session_id) do
    {:ok, entries} = FS.list(session_fs(session_id))
    Map.new(entries, &{&1.filename, &1})
  end

  defp session_fs(nil), do: nil

  defp session_fs(session_id) do
    FS.new(base_dir: OmniUI.Sessions.session_files_dir(session_id), nested: false)
  end
end
