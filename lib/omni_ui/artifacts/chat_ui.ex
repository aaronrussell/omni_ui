defmodule OmniUI.Artifacts.ChatUI do
  @moduledoc """
  Function components rendered inline in the chat stream for artifact tool
  activity.

  The entry point is `tool_use/1`, designed to be registered as a custom
  tool-use component for the files tool:

      tool_components: %{
        "files" => &OmniUI.Artifacts.ChatUI.tool_use/1
      }

  It wraps `OmniUI.Components.tool_use/1` — the default tool-use renderer —
  and slots command-specific content into its `:aside` slot. This keeps the
  default expandable's icon, toggle, and raw input/output view intact while
  adding a tool-aware control alongside the header.

  The aside is only rendered once the tool has produced a result; during
  streaming and execution the default component is shown unmodified. The
  aside content varies per command:

    * **`write` / `patch`** — a button labelled with the filename that
      dispatches a `open_artifact` event, opening the artifact in the panel.
    * **`read` / `delete`** — a short status label referencing the filename.
    * **`list`** — a "Listed files" label.
  """

  use Phoenix.Component

  alias OmniUI.Components

  @doc """
  Renders a ToolUse content block for the artifacts tool.

  Delegates to `OmniUI.Components.tool_use/1` and fills its `:aside` slot
  with command-specific content. Receives the normalised tool-use assigns
  map from `content_block/1`: `@tool_use`, `@tool_result`, `@streaming`.
  """
  attr :tool_use, :map, required: true
  attr :tool_result, :map, default: nil
  attr :streaming, :boolean, default: false

  def tool_use(assigns) do
    ~H"""
    <Components.tool_use tool_use={@tool_use} tool_result={@tool_result} streaming={@streaming}>
      <:aside :if={@tool_result}>
        <.aside
          command={@tool_use.input["command"]}
          filename={@tool_use.input["id"]} />
      </:aside>
    </Components.tool_use>
    """
  end

  attr :command, :string, required: true
  attr :filename, :string, default: nil

  defp aside(%{command: command} = assigns) when command in ["write", "patch"] do
    ~H"""
    <button
      class={[
        "inline-flex items-center gap-1.5 px-2.5 py-2 rounded-lg text-sm border transition-colors cursor-pointer",
        "text-omni-text-1 border-omni-border-3 hover:text-omni-accent-1 hover:bg-omni-accent-2/5 hover:border-omni-accent-2"
      ]}
      phx-click="open_artifact"
      phx-value-filename={@filename}>
      <Lucideicons.square_arrow_out_up_right class="size-4" />
      <span class="font-medium">{@filename}</span>
    </button>
    """
  end

  defp aside(%{command: "list"} = assigns) do
    ~H"""
    <div class="text-xs text-omni-text-4">
      Listed artifacts
    </div>
    """
  end

  defp aside(%{command: "read"} = assigns) do
    ~H"""
    <div class="text-xs text-omni-text-4">
      Read
      <span class="font-medium">{@filename}</span>
    </div>
    """
  end

  defp aside(%{command: "delete"} = assigns) do
    ~H"""
    <div class="text-xs text-omni-text-4">
      Deleted
      <span class="font-medium">{@filename}</span>
    </div>
    """
  end
end
