defmodule OmniUI.ToolsUI do
  @moduledoc """
  Custom tool-use components rendered inline in the chat stream.

  Each function is designed to be registered in the `tool_components` map
  so that `OmniUI.ChatUI.content_block/1` dispatches to it for the
  matching tool name:

      tool_components: %{
        "files" => &OmniUI.ToolsUI.files_tool_use/1,
        "repl"  => &OmniUI.ToolsUI.repl_tool_use/1
      }

  ## Files tool

  `files_tool_use/1` wraps `OmniUI.ChatUI.tool_use/1` and slots
  command-specific content into its `:aside` slot. The aside is only
  rendered once the tool has produced a result; during streaming and
  execution the default component is shown unmodified. The aside content
  varies per command:

    * **`write` / `patch`** — a button labelled with the filename that
      dispatches an `open_file` event, opening the file in the panel.
    * **`read` / `delete`** — a short status label referencing the filename.
    * **`list`** — a "Listed files" label.

  ## REPL tool

  `repl_tool_use/1` replaces the default renderer entirely:

    * The icon is a terminal instead of a cog.
    * The toggle shows the agent-provided `title` field (an active-form
      description like "Calculating average score") instead of the tool name.
    * The expanded body shows syntax-highlighted Elixir code (the `code`
      input field) instead of the raw JSON tool params.
  """

  use Phoenix.Component
  import OmniUI.CoreUI, only: [expandable: 1]

  import OmniUI.Helpers,
    only: [highlight_code: 1, highlight_code: 2, format_json: 1, format_tool_result: 1, cls: 1]

  alias OmniUI.ChatUI

  # ── Files tool ────────────────────────────────────────────────────

  @doc """
  Renders a ToolUse content block for the files tool.

  Delegates to `OmniUI.ChatUI.tool_use/1` and fills its `:aside` slot
  with command-specific content. Receives the normalised tool-use assigns
  map from `content_block/1`: `@tool_use`, `@tool_result`, `@streaming`.
  """
  attr :tool_use, :map, required: true
  attr :tool_result, :map, default: nil
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
  attr :tool_use, :map, required: true
  attr :tool_result, :map, default: nil
  attr :streaming, :boolean, default: false

  def repl_tool_use(assigns) do
    assigns =
      assigns
      |> assign(:title, Map.get(assigns.tool_use.input, "title", "Running code"))
      |> assign(:code, Map.get(assigns.tool_use.input, "code"))

    ~H"""
    <.expandable>
      <:icon>
        <Lucideicons.terminal class={cls([
          "size-4 text-omni-text-4",
          if(@streaming, do: "animate-spin", else: "")
        ])} />
      </:icon>

      <:toggle>
        <div class="flex items-center gap-2">
          <span>{@title}</span>
          <%= if @tool_result do %>
            <Lucideicons.check
              :if={@tool_result.is_error == false}
              class="size-3 text-green-500" />
            <Lucideicons.circle_x
              :if={@tool_result.is_error == true}
              class="size-4 text-red-500" />
          <% end %>
        </div>
      </:toggle>

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
