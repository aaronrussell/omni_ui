defmodule OmniUI.REPL.ChatUI do
  @moduledoc """
  Function components rendered inline in the chat stream for REPL tool
  activity.

  The entry point is `tool_use/1`, designed to be registered as a custom
  tool-use component for the REPL tool:

      {OmniUI.REPL.Tool.new(extensions: [...]),
       component: &OmniUI.REPL.ChatUI.tool_use/1}

  Unlike `Artifacts.ChatUI` (which wraps the default `Components.tool_use/1`
  and adds an `:aside` slot), this component replaces the default renderer
  entirely:

    * The icon is a terminal instead of a cog.
    * The toggle shows the agent-provided `title` field (an active-form
      description like "Calculating average score") instead of the tool name.
    * The expanded body shows syntax-highlighted Elixir code (the `code`
      input field) instead of the raw JSON tool params.
  """

  use Phoenix.Component
  import OmniUI.Components, only: [expandable: 1]

  import OmniUI.Helpers,
    only: [highlight_code: 1, highlight_code: 2, format_json: 1, format_tool_result: 1, cls: 1]

  @doc """
  Renders a ToolUse content block for the REPL tool.

  Receives the normalised tool-use assigns map from `content_block/1`:
  `@tool_use`, `@tool_result`, `@streaming`.
  """
  attr :tool_use, :map, required: true
  attr :tool_result, :map, default: nil
  attr :streaming, :boolean, default: false

  def tool_use(assigns) do
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
