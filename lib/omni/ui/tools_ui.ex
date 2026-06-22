defmodule Omni.UI.ToolsUI do
  @moduledoc """
  Custom tool-use components for the built-in tools.

  Register these in the `:tool_components` map passed to `init_session/2`
  so that `content_block/1` dispatches to them instead of the default
  `tool_use/1` renderer:

      init_session(socket,
        tool_components: %{
          "files" => &Omni.UI.ToolsUI.files_tool_use/1,
          "repl"  => &Omni.UI.ToolsUI.repl_tool_use/1
        },
        ...
      )

  `Omni.UI.AgentLive` registers both by default.
  """

  use Phoenix.Component
  import Omni.UI.CoreUI, only: [expandable: 1]

  import Omni.UI.Helpers,
    only: [highlight_code: 1, highlight_code: 2, format_json: 1, format_tool_result: 1]

  alias Omni.UI.ChatUI

  # ── Files tool ────────────────────────────────────────────────────

  @doc """
  Renders a ToolUse content block for the files tool.

  Delegates to `Omni.UI.ChatUI.tool_use/1` and fills its `:aside` slot
  with command-specific content. Receives the normalised tool-use assigns
  map from `content_block/1`: `@tool_use`, `@tool_result`, `@streaming`.
  """
  attr :tool_use, Omni.Content.ToolUse, required: true
  attr :tool_result, Omni.Content.ToolResult, default: nil
  attr :streaming, :boolean, default: false

  def files_tool_use(assigns) do
    ~H"""
    <ChatUI.tool_use tool_use={@tool_use} tool_result={@tool_result} streaming={@streaming}>
      <:aside :if={@tool_result}>
        <.files_aside
          command={@tool_use.input["command"]}
          filename={@tool_use.input["id"]} />
      </:aside>
    </ChatUI.tool_use>
    """
  end

  attr :command, :string, required: true
  attr :filename, :string, default: nil

  defp files_aside(%{command: command} = assigns) when command in ["write", "patch"] do
    ~H"""
    <button
      class={[
        "inline-flex items-center gap-1.5 px-2.5 py-2 rounded-lg text-sm border transition-colors cursor-pointer",
        "text-omni-text-1 border-omni-border-3 hover:text-omni-accent-1 hover:bg-omni-accent-2/5 hover:border-omni-accent-2"
      ]}
      phx-click="open_file"
      phx-value-filename={@filename}>
      <Lucideicons.square_arrow_out_up_right class="size-4" />
      <span class="font-medium">{@filename}</span>
    </button>
    """
  end

  defp files_aside(%{command: "list"} = assigns) do
    ~H"""
    <div class="text-xs text-omni-text-4">
      Listed files
    </div>
    """
  end

  defp files_aside(%{command: "read"} = assigns) do
    ~H"""
    <div class="text-xs text-omni-text-4">
      Read
      <span class="font-medium">{@filename}</span>
    </div>
    """
  end

  defp files_aside(%{command: "delete"} = assigns) do
    ~H"""
    <div class="text-xs text-omni-text-4">
      Deleted
      <span class="font-medium">{@filename}</span>
    </div>
    """
  end

  # ── REPL tool ─────────────────────────────────────────────────────

  @doc """
  Renders a ToolUse content block for the REPL tool.

  Receives the normalised tool-use assigns map from `content_block/1`:
  `@tool_use`, `@tool_result`, `@streaming`.
  """
  attr :tool_use, Omni.Content.ToolUse, required: true
  attr :tool_result, Omni.Content.ToolResult, default: nil
  attr :streaming, :boolean, default: false

  def repl_tool_use(assigns) do
    assigns =
      assigns
      |> assign(:title, Map.get(assigns.tool_use.input, "title", "Running code"))
      |> assign(:code, Map.get(assigns.tool_use.input, "code"))

    ~H"""
    <.expandable label={@title}>
      <:icon>
        <Lucideicons.terminal class="size-4 text-omni-text-4" />
      </:icon>

      <:status :if={@streaming}>
        <ChatUI.busy_anim />
      </:status>

      <:status :if={not @streaming and @tool_result}>
        <Lucideicons.check
          :if={not @tool_result.is_error}
          class="size-3 text-green-500" />
        <Lucideicons.circle_x
          :if={@tool_result.is_error}
          class="size-4 text-red-500" />
      </:status>

      <div
        class={[
          "space-y-3",
          "[&_pre]:m-0! [&_pre]:px-4 [&_pre]:py-3 [&_pre]:max-h-48 [&_pre]:rounded",
          "[&_pre]:text-xs [&_pre]:overflow-auto"
        ]}>
        <div>
          <span class="block mb-1 text-xs text-omni-text-2">{if(@code, do: "Code", else: "Input")}:</span>
          <%= if @code do %>
            <%= highlight_code(@code, "elixir") %>
          <% else %>
            <%= highlight_code(format_json(@tool_use.input), "json") %>
          <% end %>
        </div>

        <div
          :if={@tool_result}
          class={if(@tool_result.is_error, do: "[&_pre]:ring-2 [&_pre]:ring-offset-2 [&_pre]:ring-red-500")}>
          <span class="block mb-1 text-xs text-omni-text-2">Output:</span>
          <%= highlight_code(format_tool_result(@tool_result)) %>
        </div>
      </div>
    </.expandable>
    """
  end
end
