defmodule OmniUI.Artifacts.Components do
  use Phoenix.Component
  alias OmniUI.Artifacts.Artifact

  attr :artifact, Artifact, default: nil
  attr :view_source, :boolean, default: false
  attr :token, :string, required: true
  attr :target, :any, default: nil

  def artifact_bar(assigns) do
    ~H"""
    <div class="flex items-center gap-4 h-12 p-4 border-b border-omni-border-2">
      <Lucideicons.monitor class="size-4" />
      <div class="font-semibold text-omni-text">
        {if(@artifact, do: @artifact.filename, else: "All artifacts")}
      </div>

      <div
        :if={@artifact}
        class="flex-auto flex items-center gap-2 justify-end">

        <div
          :if={toggleable?(@artifact)}
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

  def artifact_list(assigns) do
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
            <div>{format_bytes(artifact.size)}</div>
            <div>{Calendar.strftime(artifact.updated_at, "%d %b %Y, %I:%M%P")}</div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  def artifact_view(%{view: :iframe} = assigns) do
    ~H"""
    <iframe
      src={artifact_url(@token, @artifact.filename)}
      sandbox={if(@artifact.mime_type == "text/html", do: "allow-scripts")}
      class="size-full border-0" />
    """
  end

  def artifact_view(%{view: :markdown} = assigns) do
    ~H"""
    <div class="min-h-full p-12 pb-16 bg-omni-bg-1">
      <div class="max-w-xl mx-auto mdex leading-[1.5]">
        {@content}
      </div>
    </div>
    """
  end

  def artifact_view(%{view: :source} = assigns) do
    ~H"""
    <div
      class={[
        "min-h-full",
        "[&>pre]:min-h-full [&>pre]:m-0 [&>pre]:p-12 [&>pre]:text-sm",
        "[&>pre]:whitespace-pre-wrap"
      ]}>
      {@content}
    </div>
    """
  end

  def artifact_view(%{view: :media} = assigns) do
    ~H"""
    <div class="min-h-full flex items-center justify-center p-12 pb-16 bg-omni-bg-1">
      <img
        src={artifact_url(@token, @artifact.filename)}
        alt={@artifact.filename}
        class="max-w-full h-auto border border-omni-border-2"
      />
    </div>
    """
  end

  def artifact_view(%{view: :download} = assigns) do
    ~H"""
    <div class="h-full flex items-center justify-center p-12">
      <button
        href={artifact_url(@token, @artifact.filename)}
        download={@artifact.filename}
        class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-omni-accent-1 text-white font-medium hover:bg-omni-accent-2 transition-colors">
        <Lucideicons.download class="size-4" />
        <span>Download</span>
      </button>
    </div>
    """
  end

  # ---- HELPERS

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"

  defp toggleable?(%Artifact{mime_type: mime_type})
       when mime_type in ["text/html", "text/markdown", "image/svg+xml"],
       do: true

  defp toggleable?(_), do: false

  defp artifact_url(token, filename) do
    "#{url_prefix()}/#{token}/#{URI.encode(filename)}"
  end

  defp url_prefix do
    Application.get_env(:omni_ui, OmniUI.Artifacts, [])
    |> Keyword.get(:url_prefix, "/omni_artifacts")
  end
end
