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

    * **Preview** (`text/html`, `application/pdf`) — iframe loading from the
      artifact Plug route; HTML gets `sandbox="allow-scripts"`, PDF uses
      the browser's native viewer
    * **Rendered** (`text/markdown`) — MDEx-rendered HTML with typography styles
    * **Image** (`image/*` including `image/svg+xml`) — centered `<img>` tag
      served from the artifact Plug route
    * **Code** (`text/*`, `application/json`, and other text-like types) —
      syntax-highlighted source via Lumis with inline styles
    * **Download** (everything else) — download link

  HTML, Markdown, and SVG artifacts support a **Preview / Code toggle** in the
  artifact bar, allowing users to switch between the rendered view and the
  syntax-highlighted source.
  """

  use Phoenix.LiveComponent

  import OmniUI.Helpers, only: [to_md: 1]

  alias OmniUI.Artifacts.{FileSystem, URL}

  @text_like_app_types ~w(
    application/json application/javascript application/xml
    application/x-yaml application/x-sh application/sql
  )

  # Synced from OmniUI.Components @markdown_styles — keep in sync
  @markdown_styles ~w"""
  [&_.mdex>*:first-child]:mt-0! [&_.mdex>*:last-child]:mb-0!
  [&_.mdex_p,ul,ol,h1,h2,h3,h4,h5,h6]:mb-4 [&_.mdex_p,ul,ol,h1,h2,h3,h4,h5,h6]:max-w-prose
  [&_.mdex_h1,h2]:mt-12 [&_.mdex_h3]:mt-6
  [&_.mdex_h1,h2,h4,h5,h6]:font-bold [&_.mdex_h3,h5]:italic
  [&_.mdex_h1]:text-3xl [&_.mdex_h1]:font-black
  [&_.mdex_h2]:text-2xl [&_.mdex_h2]:font-bold
  [&_.mdex_h3]:text-xl [&_.mdex_h3]:font-bold
  [&_.mdex_h4]:text-lg [&_.mdex_h4]:font-bold
  [&_.mdex_h5]:font-bold
  [&_.mdex_h6]:font-medium [&_.mdex_h6]:italic
  [&_.mdex_ul]:list-disc [&_.mdex_ul]:pl-5
  [&_.mdex_ol]:list-decimal [&_.mdex_ol]:pl-5
  [&_.mdex_li]:my-0.5
  [&_.mdex_table,pre,img,hr]:my-6
  [&_.mdex_table]:w-full [&_.mdex_table]:table-fixed [&_.mdex_table]:text-sm
  [&_.mdex_table]:border [&_.mdex_table]:border-separate [&_.mdex_table]:border-spacing-0 [&_.mdex_table]:rounded-xl
  [&_.mdex_table]:border-omni-border-3
  [&_.mdex_thead_th]:border-b [&_.mdex_thead_th]:border-omni-border-3
  [&_.mdex_th,td]:text-left [&_.mdex_th,td]:p-2.5
  [&_.mdex_tbody>tr]:odd:bg-omni-bg-2
  [&_.mdex_pre]:-mx-6 [&_.mdex_pre]:px-6 [&_.mdex_pre]:py-5 [&_.mdex_pre]:rounded-xl [&_.mdex_pre]:overflow-y-scroll
  [&_.mdex_hr]:h-px [&_.mdex_hr]:bg-omni-border-2 [&_.mdex_hr]:border-none
  [&_.mdex_a]:font-medium [&_.mdex_a]:hover:underline [&_.mdex_a]:transition-colors
  [&_.mdex_a]:text-omni-accent-1 [&_.mdex_a]:hover:text-omni-accent-2
  [&_.mdex_code]:text-sm [&_.mdex_code]:leading-[1.625] [&_.mdex_code]:font-mono
  [&_.mdex_:not(pre)>code]:px-1 [&_.mdex_:not(pre)>code]:py-0.5 [&_.mdex_:not(pre)>code]:rounded-sm
  [&_.mdex_:not(pre)>code]:bg-omni-bg-1
  """

  # ── Lifecycle ────────────────────────────────────────────────────

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       artifacts: %{},
       active_artifact: nil,
       content: nil,
       view_mode: :primary,
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
         |> assign(
           artifacts: scan(new_session_id),
           active_artifact: nil,
           content: nil,
           view_mode: :primary
         )
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
    {:noreply, assign(socket, active_artifact: filename, content: content, view_mode: :primary)}
  end

  def handle_event("toggle_view", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :view_mode, String.to_existing_atom(mode))}
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
        view_mode={@view_mode}
        token={@token}
        target={@myself} />

      <%= if @active_artifact do %>
        <.artifact_viewer
          artifact={@artifacts[@active_artifact]}
          content={@content}
          view_mode={@view_mode}
          token={@token}
          target={@myself} />
      <% else %>
        <.artifact_list artifacts={@artifacts} target={@myself} />
      <% end %>
    </div>
    """
  end

  defp artifact_bar(assigns) do
    assigns =
      assign(assigns, :toggleable, assigns.artifact && toggleable?(assigns.artifact.mime_type))

    ~H"""
    <div class="flex items-center gap-4 h-12 p-4 border-b border-omni-border-2">
      <Lucideicons.monitor class="size-4" />
      <div class="font-semibold text-omni-text">{if(@artifact, do: @artifact.filename, else: "All artifacts")}</div>

      <div
        :if={@artifact}
        class="flex-auto flex items-center gap-2 justify-end">

        <div :if={@toggleable} class="flex items-center rounded-lg bg-omni-bg-1 p-0.5 text-xs font-medium">
          <button
            phx-click="toggle_view" phx-value-mode="primary" phx-target={@target}
            class={[
              "px-2.5 py-1 rounded-md transition-colors cursor-pointer",
              if(@view_mode == :primary,
                do: "bg-omni-bg text-omni-text shadow-sm",
                else: "text-omni-text-3 hover:text-omni-text-1")
            ]}>
            {primary_label(@artifact.mime_type)}
          </button>
          <button
            phx-click="toggle_view" phx-value-mode="code" phx-target={@target}
            class={[
              "px-2.5 py-1 rounded-md transition-colors cursor-pointer",
              if(@view_mode == :code,
                do: "bg-omni-bg text-omni-text shadow-sm",
                else: "text-omni-text-3 hover:text-omni-text-1")
            ]}>
            Code
          </button>
        </div>

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
    mode = render_mode(assigns.artifact.mime_type)

    effective_mode =
      if assigns.view_mode == :code and toggleable?(assigns.artifact.mime_type),
        do: :code,
        else: mode

    assigns = assign(assigns, :mode, effective_mode)

    ~H"""
    <.viewer_content mode={@mode} artifact={@artifact} content={@content} token={@token} />
    <!--
    <div class="h-full flex flex-col">
      <div class="flex-1 min-h-0">
        <.viewer_content mode={@mode} artifact={@artifact} content={@content} token={@token} />
      </div>
    </div>
    -->
    """
  end

  # ── Render modes ─────────────────────────────────────────────────

  defp viewer_content(%{mode: :preview} = assigns) do
    ~H"""
    <iframe
      src={artifact_url(@token, @artifact.filename)}
      sandbox={if(@artifact.mime_type == "text/html", do: "allow-scripts")}
      class="w-full flex-auto border-0"
    />
    """
  end

  defp viewer_content(%{mode: :rendered} = assigns) do
    assigns = assign(assigns, :md_styles, @markdown_styles)

    ~H"""
    <div class={["h-full overflow-auto p-12 text-base text-omni-text" | @md_styles]}>
      <div class="mdex leading-[1.5]">
        {@content.primary}
      </div>
    </div>
    """
  end

  defp viewer_content(%{mode: :image} = assigns) do
    ~H"""
    <div class="h-full flex items-center justify-center p-12 overflow-auto">
      <img
        src={artifact_url(@token, @artifact.filename)}
        alt={@artifact.filename}
        class="max-w-full max-h-full border border-omni-border-1"
      />
    </div>
    """
  end

  defp viewer_content(%{mode: :code} = assigns) do
    ~H"""
    <div
      class={[
        "flex-auto overflow-auto",
        "[&>pre]:min-h-full [&>pre]:p-12 [&>pre]:text-sm"
      ]}>
      {@content.code}
    </div>
    """
  end

  defp viewer_content(%{mode: :download} = assigns) do
    ~H"""
    <div class="h-full flex flex-col items-center justify-center gap-4 p-4">
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
      mime_type == "text/html" -> :preview
      mime_type == "text/markdown" -> :rendered
      mime_type == "application/pdf" -> :preview
      mime_type == "image/svg+xml" -> :image
      String.starts_with?(mime_type, "image/") -> :image
      String.starts_with?(mime_type, "text/") -> :code
      mime_type in @text_like_app_types -> :code
      true -> :download
    end
  end

  defp toggleable?(mime_type) do
    mime_type in ["text/html", "text/markdown", "image/svg+xml"]
  end

  defp primary_label(mime_type) do
    case render_mode(mime_type) do
      :image -> "Image"
      _ -> "Preview"
    end
  end

  defp load_content(artifact, session_id) do
    mode = render_mode(artifact.mime_type)
    toggleable = toggleable?(artifact.mime_type)

    cond do
      mode == :download ->
        nil

      mode in [:preview, :image] and not toggleable ->
        nil

      true ->
        {:ok, raw} = FileSystem.read(artifact.filename, session_id: session_id)

        code =
          Lumis.highlight!(raw,
            language: artifact.filename,
            formatter: {:html_inline, theme: "catppuccin_macchiato"}
          )
          |> Phoenix.HTML.raw()

        primary =
          case mode do
            :rendered -> to_md(raw)
            _ -> nil
          end

        %{primary: primary, code: code}
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
