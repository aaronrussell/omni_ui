defmodule OmniUI.ChatUI do
  @moduledoc """
  Function components for the chat rendering pipeline.

  All components use the semantic color tokens defined in `priv/static/omni_ui.css`
  and are designed to be composed within a `chat_interface/1` root.

  ## Layout

    * `chat_interface/1` — root wrapper, provides scroll container, editor, and
      markdown typography styles
    * `message_list/1` — vertical list of turns
    * `turn/1` — pairs a `:user` slot with an optional `:assistant` slot

  ## Messages

    * `user_message/1` — renders user text and attachment content blocks
    * `assistant_message/1` — renders assistant content blocks with streaming support
    * `user_message_actions/1` — copy, edit, and version navigation for user messages
    * `assistant_message_actions/1` — copy, redo, version navigation, and usage display

  ## Content blocks

    * `content_block/1` — pattern-matched renderer for `Text`, `Thinking`,
      `ToolUse`, and `Attachment` content types
    * `markdown/1` — converts markdown text to styled HTML via MDEx
    * `tool_use/1` — default tool-use renderer with expandable input/output
    * `attachment/1` — thumbnail tile for images and file icons

  ## Toolbar

    * `toolbar/1` — model selector, thinking toggle, and usage summary
  """

  use Phoenix.Component
  import OmniUI.CoreUI
  import OmniUI.Helpers
  alias Phoenix.LiveView.JS

  # ── Layout ──────────────────────────────────────────────────────

  @doc """
  Root layout for the chat interface.

  Provides the scroll container, message editor, and markdown typography
  styles. All other components are designed to be rendered within this root.
  """
  slot :inner_block, required: true
  slot :toolbar
  slot :footer

  def chat_interface(assigns) do
    ~H"""
    <div
      class={[
        "omni-ui flex flex-col h-full [interpolate-size:allow-keywords]",
        "bg-omni-bg text-omni-text"
        | md_styles()
      ]}>
      <div id="omni-view" class="flex-auto px-12 overflow-y-scroll">
        <div
          id="omni-content"
          class={[
            "max-w-3xl mx-auto flex flex-col px-12 py-16 gap-24",
            "min-h-[var(--scroll-lock,auto)]"
          ]}>
          {render_slot(@inner_block)}
          <div id="omni-sentinel" class="h-0" />
        </div>
      </div>

      <div
        class={[
          "shrink-0 px-12",
          if(@footer == [], do: "pb-8", else: "pb-6")]
        }>
        <div class="max-w-3xl mx-auto flex flex-col items-center gap-6">
          <.live_component id="editor" module={OmniUI.EditorComponent}>
            <:toolbar :for={item <- @toolbar} align={item[:align]}>
              {render_slot(item)}
            </:toolbar>
          </.live_component>

          <div :if={@footer != []} class={[
            "text-xs text-omni-text-4",
            "[&_a]:text-omni-text-3 [&_a]:underline [&_a]:transition-colors",
            "[&_a]:hover:text-omni-accent-2",
          ]}>
            {render_slot(@footer)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc "Vertical list container for turns."
  attr :rest, :global
  slot :inner_block, required: true

  def message_list(assigns) do
    ~H"""
    <div class="flex flex-col gap-24 empty:hidden" {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "Pairs a `:user` slot with an optional `:assistant` slot."
  attr :rest, :global
  slot :user, required: true
  slot :assistant

  def turn(assigns) do
    ~H"""
    <div class="flex flex-col gap-24" {@rest}>
      <div class="flex flex-col items-end gap-6">
        {render_slot(@user)}
      </div>
      <div :if={@assistant != []} class="flex flex-col gap-6">
        {render_slot(@assistant)}
      </div>
    </div>
    """
  end

  # ── Messages ────────────────────────────────────────────────────

  @doc "Renders user text and attachment content blocks in a styled bubble."
  attr :text, :list, required: true
  attr :attachments, :list, required: true

  def user_message(assigns) do
    ~H"""
    <div class={[
      "relative flex flex-col gap-4 px-4 py-2.5 rounded-xl",
      "bg-omni-bg-1 text-omni-text-1",
    ]}>
      <div
        :if={@text != []}
        class="flex flex-col gap-4">
        <.content_block
          :for={content <- @text}
          content={content} />
      </div>

      <div
        :if={@attachments != []}
        class="flex flex-wrap gap-3">
        <.content_block
          :for={content <- @attachments}
          content={content} />
      </div>
    </div>
    """
  end

  @doc "Copy, edit, and version navigation actions for a user message."
  attr :turn_id, :integer, required: true
  attr :versions, :list, required: true
  attr :timestamp, DateTime, required: true
  attr :target, :any, default: nil

  def user_message_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-4">
      <.timestamp
        class="text-xs text-omni-text-4"
        time={@timestamp}
        format="%-d %B" />

      <button
        phx-click={
          JS.push("copy_message", value: %{role: "user"}, target: @target)
          |> JS.transition("success", time: 2000, blocking: false)
        }
        class={[
          "group flex items-center gap-1.5 text-xs transition-colors cursor-pointer",
          "text-omni-text-3 hover:text-omni-accent-1"
        ]}>
        <Lucideicons.copy class="size-3 group-[.success]:hidden" />
        <Lucideicons.check class="size-3 hidden group-[.success]:block text-green-500" />
        <span class="group-[.success]:hidden">Copy</span>
        <span class="hidden group-[.success]:inline text-green-500">Copied!</span>
      </button>

      <button
        phx-click={JS.push("edit", target: @target)}
        class={[
          "flex items-center gap-1.5 text-xs transition-colors cursor-pointer",
          "text-omni-text-3 hover:text-omni-accent-1"
        ]}>
        <Lucideicons.pencil class="size-3" />
        <span>Edit</span>
      </button>

      <.version_nav
        :if={length(@versions) > 1}
        version_id={@turn_id}
        versions={@versions} />
    </div>
    """
  end

  @doc "Renders assistant content blocks with streaming support."
  attr :content, :list, required: true
  attr :tool_results, :map, required: true
  attr :streaming, :boolean, required: true
  attr :tool_components, :map, default: %{}

  def assistant_message(assigns) do
    ~H"""
    <div>
      <div class="flex flex-col gap-4">
        <.content_block
          :for={{content, idx} <- Enum.with_index(@content)}
          content={content}
          tool_results={@tool_results}
          tool_components={@tool_components}
          streaming={@streaming and idx == length(@content) - 1} />
      </div>

      <!-- TODO - message error -->
    </div>
    """
  end

  @doc "Copy, redo, version navigation, and usage display for an assistant message."
  attr :turn_id, :integer, required: true
  attr :node_id, :integer, required: true
  attr :versions, :list, required: true
  attr :usage, Omni.Usage, required: true
  attr :target, :any, default: nil

  def assistant_message_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-4">
      <button
        phx-click={
          JS.push("copy_message", value: %{role: "assistant"}, target: @target)
          |> JS.transition("success", time: 2000, blocking: false)
        }
        class={[
          "group flex items-center gap-1.5 text-xs transition-colors cursor-pointer",
          "text-omni-text-3 hover:text-omni-accent-1"
        ]}>
        <Lucideicons.copy class="size-3 group-[.success]:hidden" />
        <Lucideicons.check class="size-3 hidden group-[.success]:block text-green-500" />
        <span class="group-[.success]:hidden">Copy</span>
        <span class="hidden group-[.success]:inline text-green-500">Copied!</span>
      </button>

      <button
        phx-click={
          JS.dispatch("omni:before-update")
          |> JS.push("omni:regenerate", value: %{turn_id: @turn_id})
        }
        class={[
          "flex items-center gap-1.5 text-xs transition-colors cursor-pointer",
          "text-omni-text-3 hover:text-omni-accent-1"
        ]}>
        <Lucideicons.rotate_cw class="size-3" />
        <span>Redo</span>
      </button>

      <.version_nav
        :if={length(@versions) > 1}
        version_id={@node_id}
        versions={@versions} />

      <div class="flex-auto flex justify-end">
        <.usage_block usage={@usage} />
      </div>
    </div>
    """
  end

  # ── Content blocks ──────────────────────────────────────────────

  @doc """
  Pattern-matched renderer for content types.

  Dispatches on the struct type of the `:content` assign to render `Text`,
  `Thinking`, `ToolUse`, or `Attachment` blocks.

  For `ToolUse` blocks, consults the `:tool_components` map (keyed by tool
  name) for a custom component. If no entry exists, falls back to the default
  tool-use rendering.

  Custom tool-use components receive a normalised assigns map with three keys:

    * `@tool_use` — the `%Omni.Content.ToolUse{}` struct
    * `@tool_result` — the matching `%Omni.Content.ToolResult{}` or `nil` if
      not yet available (pre-resolved from the `:tool_results` map)
    * `@streaming` — boolean, `true` if this is the last block of a streaming
      message
  """
  attr :content, :map, required: true
  attr :tool_results, :map, default: %{}
  attr :tool_components, :map, default: %{}
  attr :streaming, :boolean, default: false

  def content_block(%{content: %Omni.Content.Text{}} = assigns) do
    ~H"""
    <.markdown text={@content.text} streaming={@streaming} class="text-base" />
    """
  end

  def content_block(%{content: %Omni.Content.Thinking{}} = assigns) do
    ~H"""
    <.expandable label={if(@streaming, do: "Thinking", else: "Thought")}>
      <:icon>
        <Lucideicons.sparkle
          class={cls([
          "size-4 text-amber-500",
          if(@streaming, do: "animate-spin", else: "")
        ])} />
      </:icon>

      <.markdown text={@content.text} class="text-sm text-omni-text-3 italic" />
    </.expandable>
    """
  end

  def content_block(%{content: %Omni.Content.Attachment{}} = assigns) do
    ~H"""
    <.attachment name={@content.media_type} media_type={@content.media_type}>
      <:image :if={match?("image/" <> _, @content.media_type)}>
        <img src={attachment_url(@content)} />
      </:image>
    </.attachment>
    """
  end

  def content_block(%{content: %Omni.Content.ToolUse{} = tool_use} = assigns) do
    tool_use_assigns = %{
      __changed__: nil,
      tool_use: tool_use,
      tool_result: assigns[:tool_results][tool_use.id],
      streaming: assigns[:streaming] || false
    }

    case assigns[:tool_components][tool_use.name] do
      nil -> tool_use(tool_use_assigns)
      fun when is_function(fun, 1) -> fun.(tool_use_assigns)
    end
  end

  @doc """
  Default rendering for a `ToolUse` content block.

  Used by `content_block/1` when no custom component is registered for a tool
  in `:tool_components`. Custom tool-use components can also delegate to this
  function — for example, to add a per-tool control via the `:aside` slot —
  by calling `ChatUI.tool_use/1` with the normalised assigns map.
  """
  attr :tool_use, :map, required: true, doc: "the `%Omni.Content.ToolUse{}` struct"

  attr :tool_result, :map,
    default: nil,
    doc: "the matching `%Omni.Content.ToolResult{}`, or `nil` if not yet available"

  attr :streaming, :boolean,
    default: false,
    doc: "`true` if this is the last block of a streaming message"

  slot :aside,
    doc: "optional content rendered alongside the header, outside the expandable's click target"

  def tool_use(assigns) do
    ~H"""
    <.expandable>
      <:icon>
        <Lucideicons.cog class={cls([
          "size-4 text-omni-text-4",
          if(@streaming, do: "animate-spin", else: "")
        ])} />
      </:icon>

      <:toggle>
        <div class="flex items-center gap-1">
          <code class={[
            "px-2 py-1 rounded font-mono text-xs",
            "bg-omni-bg-1 text-omni-text-1"
          ]}><%= @tool_use.name %></code>
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

      <:aside :if={@aside != []}>{render_slot @aside}</:aside>

      <div
        class={[
          "space-y-3",
          "[&_pre]:m-0! [&_pre]:px-4 [&_pre]:py-3 [&_pre]:max-h-48 [&_pre]:rounded",
          "[&_pre]:text-xs [&_pre]:overflow-auto"
        ]}>
        <div class="[&_pre]:text-wrap">
          <span class="block mb-1 text-xs text-omni-text-2">Input:</span>
          <%= highlight_code(format_json(@tool_use.input), "json") %>
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

  @doc """
  Thumbnail tile for file attachments.

  Renders an image preview via the `:image` slot, or a file icon fallback
  for non-image types. The `:action` slot is used for overlay controls
  (e.g. a cancel button in the editor).
  """
  attr :name, :string, required: true
  attr :media_type, :string, required: true
  attr :rest, :global
  slot :image
  slot :action

  def attachment(assigns) do
    ~H"""
    <div class="relative group" {@rest}>
      <div class={[
        "size-16 border rounded-lg overflow-hidden",
        "bg-omni-bg text-omni-text-3 border-omni-border-2",
        "[&_img]:block [&_img]:size-16 [&_img]:object-cover"
      ]}>
        <div
          :if={@image == [] and not match?("image/" <> _, @media_type)}
          class="size-full flex flex-col items-center justify-center gap-2 p-2">
          <Lucideicons.paperclip class="size-4" />
          <div class="w-full text-[10px] leading-[12px] text-center break-all truncate">
            {@name}
          </div>
        </div>

        {render_slot(@image)}
      </div>
      {render_slot(@action)}
    </div>
    """
  end

  @doc """
  Converts markdown text to styled HTML.

  Rendering is handled by `OmniUI.Helpers.to_md/2`. Typography styles are
  applied via descendant selectors on `chat_interface/1` targeting the `.md`
  class — see `@markdown_styles`.
  """
  attr :text, :string, required: true
  attr :streaming, :boolean, default: false
  attr :rest, :global

  def markdown(assigns) do
    ~H"""
    <div class={["mdex leading-[1.5]", @rest.class]}>
      <%= to_md(@text, streaming: @streaming) %>
    </div>
    """
  end

  # ── Toolbar ─────────────────────────────────────────────────────

  @doc """
  Toolbar with model selector, thinking toggle, and usage summary.

  All attrs are optional — sections are only rendered when their data is
  provided, allowing consumers to show a subset of controls.

  `model_options` accepts a list of `%Omni.Model{}` structs; the toolbar
  groups them by provider for the select dropdown. The thinking selector
  renders when `thinking` is not nil and the current model supports reasoning.
  """
  attr :model_options, :list, default: nil
  attr :model, Omni.Model, default: nil
  attr :thinking, :atom, default: nil
  attr :usage, Omni.Usage, default: nil

  @thinking_levels [:max, :high, :medium, :low, false]

  def toolbar(assigns) do
    assigns =
      assigns
      |> assign_new(:formatted_model_options, fn ->
        format_model_options(assigns.model_options)
      end)
      |> assign_new(:formatted_thinking_options, fn -> format_thinking_options() end)

    ~H"""
    <div class="flex flex-auto items-center gap-4">
      <div
        :if={@formatted_model_options && @model}
        class={[
          "flex items-center gap-4",
          "before:content=[''] before:w-px before:h-3 before:bg-omni-border-2"
        ]}>
        <.select
          id="model-select"
          options={@formatted_model_options}
          value={model_key(@model)}
          event="omni:select_model"
          position="above" />
      </div>

      <div
        :if={@thinking != nil && @model && @model.reasoning}
        class={[
          "flex items-center gap-4",
          "before:content=[''] before:w-px before:h-3 before:bg-omni-border-2"
        ]}>
        <.select
          id="thinking-select"
          options={@formatted_thinking_options}
          value={to_string(@thinking)}
          event="omni:select_thinking"
          prompt="Thinking"
          position="above" />
      </div>

      <div :if={@usage} class="flex-auto flex items-center justify-end">
        <.usage_block usage={@usage} />
      </div>
    </div>
    """
  end

  defp format_thinking_options do
    Enum.map(@thinking_levels, fn val ->
      value = to_string(val)
      label = if val == false, do: "Off", else: String.capitalize(value)
      %{value: value, label: label}
    end)
  end
end
