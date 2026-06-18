defmodule OmniUI.FilesUI do
  @moduledoc """
  Function components for the files panel.

    * `file_bar/1` — header with filename, view toggle, download, and close
    * `file_list/1` — directory listing with name, size, and updated columns
    * `file_view/1` — pattern-matched file viewer (iframe, markdown, source,
      media, download)
  """

  use Phoenix.Component
  alias Omni.Tools.Files.Entry

  attr :file, Entry, default: nil
  attr :view_source, :boolean, default: false
  attr :token, :string, required: true
  attr :target, :any, default: nil

  def file_bar(assigns) do
    ~H"""
    <header class="flex items-center gap-4 h-12 p-4 border-b border-omni-border-3">
      <%= if @file do %>
        <button
          class={[
            "flex items-center justify-center size-8 rounded cursor-pointer",
            "text-omni-text-1 hover:text-omni-accent-1 hover:bg-omni-accent-2/10"
          ]}
          phx-click="close_file"
          phx-target={@target}>
          <Lucideicons.arrow_left class="size-4" />
        </button>
      <% else %>
        <div class="flex items-center justify-center size-8">
          <Lucideicons.list class="size-4" />
        </div>
      <% end %>

      <h2 class="text-sm font-medium text-omni-text-1">
        {if(@file, do: @file.filename, else: "All files")}
      </h2>

      <div class="flex-auto flex items-center gap-1 justify-end">
        <div
          :if={toggleable?(@file)}
          class="flex items-center rounded-lg bg-omni-bg-1 p-0.5 text-xs font-medium">
          <button
            phx-click="toggle_view" phx-target={@target}
            class={[
              "px-2.5 py-1 rounded-md transition-colors cursor-pointer",
              if(@view_source == false,
                do: "bg-omni-bg text-omni-text shadow-sm",
                else: "text-omni-text-3 hover:text-omni-text-1")
            ]}>
            Preview
          </button>
          <button
            phx-click="toggle_view" phx-target={@target}
            class={[
              "px-2.5 py-1 rounded-md transition-colors cursor-pointer",
              if(@view_source == true,
                do: "bg-omni-bg text-omni-text shadow-sm",
                else: "text-omni-text-3 hover:text-omni-text-1")
            ]}>
            Code
          </button>
        </div>

        <a
          :if={@file}
          class={[
            "flex items-center justify-center size-8 rounded transition-colors cursor-pointer",
            "text-omni-text-1 hover:text-omni-accent-1 hover:bg-omni-accent-2/10"
          ]}
          href={file_url(@token, @file.filename)}
          download={@file.filename}>
          <Lucideicons.download class="size-4" />
        </a>

        <button
          class={[
            "flex items-center justify-center size-8 rounded cursor-pointer",
            "text-omni-text-1 hover:text-omni-accent-1 hover:bg-omni-accent-2/10"
          ]}
          title="Close files"
          phx-click="toggle_files">
          <Lucideicons.x class="size-4" />
        </button>
      </div>
    </header>
    """
  end

  attr :files, :map, required: true
  attr :error, :string, default: nil
  attr :target, :any, default: nil

  def file_list(assigns) do
    ~H"""
    <div class="size-full p-6 flex flex-col overflow-y-auto">
      <div :if={@error} class="flex items-center gap-3 mb-4 px-4 py-3 text-red-600 bg-omni-bg-2 border border-red-500 rounded">
        <Lucideicons.triangle_alert class="size-4" />
        <p class="text-sm">{@error}</p>
      </div>

      <%= if @files == %{} do %>
        <div class="flex-1 flex items-center justify-center">
          <p class="text-sm text-omni-text-3 italic">No files yet.</p>
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
          :for={{filename, file} <- Enum.sort(@files)}
          class="border-b border-omni-border-3">
          <div
            class={[
              "px-2 py-3 grid grid-cols-[50%_1fr_1fr] gap-x-4 text-sm text-omni-text-3 group cursor-pointer transition-colors",
              "hover:bg-omni-bg-2"
            ]}
            phx-click="select_file"
            phx-value-filename={filename}
            phx-target={@target}>
            <div class={[
              "flex items-center gap-2 transition-colors",
              "text-omni-text-1 group-hover:text-omni-accent-1"
            ]}>
              <Lucideicons.file_code class="size-4" />
              <span class="font-medium">{filename}</span>
            </div>
            <div>{format_bytes(file.size)}</div>
            <div>{Calendar.strftime(file.mtime, "%d %b %Y, %I:%M%P")}</div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  def file_view(%{view: :iframe} = assigns) do
    ~H"""
    <iframe
      src={file_url(@token, @file.filename)}
      sandbox={if(@file.media_type == "text/html", do: "allow-scripts")}
      class="size-full border-0" />
    """
  end

  def file_view(%{view: :markdown} = assigns) do
    ~H"""
    <div class="min-h-full p-6">
      <div class="max-w-xl mx-auto mdex leading-[1.5]">
        {@content}
      </div>
    </div>
    """
  end

  def file_view(%{view: :source} = assigns) do
    ~H"""
    <div
      class={[
        "h-full",
        "[&>pre]:min-h-full! [&>pre]:m-0 [&>pre]:p-6 [&>pre]:text-sm",
        "[&>pre]:whitespace-pre-wrap"
      ]}>
      {@content}
    </div>
    """
  end

  def file_view(%{view: :media} = assigns) do
    ~H"""
    <div class="min-h-full flex items-center justify-center p-6 bg-omni-bg-1">
      <img
        src={file_url(@token, @file.filename)}
        alt={@file.filename}
        class="max-w-full h-auto border border-omni-border-2"
      />
    </div>
    """
  end

  def file_view(%{view: :download} = assigns) do
    ~H"""
    <div class="h-full flex items-center justify-center p-6">
      <a
        href={file_url(@token, @file.filename)}
        download={@file.filename}
        class={[
          "inline-flex items-center gap-1.5 px-3 py-2 rounded-lg text-sm border transition-colors cursor-pointer",
          "text-omni-text-1 border-omni-border-3 hover:text-omni-accent-1 hover:bg-omni-accent-2/5 hover:border-omni-accent-2"
        ]}>
        <Lucideicons.download class="size-4" />
        <span class="font-medium">Download</span>
      </a>
    </div>
    """
  end

  # ---- HELPERS

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"

  defp toggleable?(%Entry{media_type: mime_type})
       when mime_type in ["text/html", "text/markdown", "image/svg+xml"],
       do: true

  defp toggleable?(_), do: false

  defp file_url(token, filename) do
    "#{url_prefix()}/#{token}/#{URI.encode(filename)}"
  end

  defp url_prefix do
    Application.get_env(:omni_ui, OmniUI.Files, [])
    |> Keyword.get(:url_prefix, "/omni_files")
  end
end
