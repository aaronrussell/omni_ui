defmodule OmniUI.Components do
  @moduledoc """
  Function components for building agent chat interfaces.

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
    * `attachment/1` — thumbnail tile for images and file icons

  ## UI primitives

    * `expandable/1` — collapsible section with icon and toggle
    * `version_nav/1` — prev/next navigation with position display
    * `timestamp/1` — formatted time display
    * `usage_block/1` — compact token count and cost display
    * `toolbar/1` — model selector, thinking toggle, and usage summary
    * `select/1` — dropdown select with grouped options
  """

  use Phoenix.Component
  import OmniUI.Helpers
  alias Phoenix.LiveView.JS

  # Markdown typography styles applied at the chat_interface level via descendant
  # selectors targeting the `.mdex` class. This keeps the markdown component's HTML
  # minimal while defining styles once in the DOM.
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
    assigns = assign(assigns, :markdown_styles, @markdown_styles)

    ~H"""
    <div
      class={[
        "omni-ui flex flex-col h-full [interpolate-size:allow-keywords]",
        "bg-omni-bg text-omni-text"
        | @markdown_styles
      ]}>
      <div id="omni-view" class="flex-auto overflow-y-scroll">
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

      <div class={["shrink-0", if(@footer == [], do: "pb-8", else: "pb-6")]}>
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
      <.timestamp time={@timestamp} />

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

  def assistant_message(assigns) do
    ~H"""
    <div>
      <div class="flex flex-col gap-4">
        <.content_block
          :for={content <- @content}
          content={content}
          tool_results={@tool_results}
          streaming={@streaming} />
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
  """
  attr :content, :map, required: true
  attr :tool_results, :map, default: %{}
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

  # TODO: Pass actual filename once Omni.Content.Attachment includes one.
  # Currently falls back to media_type as the display name.
  def content_block(%{content: %Omni.Content.Attachment{}} = assigns) do
    ~H"""
    <.attachment name={@content.media_type} media_type={@content.media_type}>
      <:image :if={match?("image/" <> _, @content.media_type)}>
        <img src={attachment_url(@content)} />
      </:image>
    </.attachment>
    """
  end

  def content_block(%{content: %Omni.Content.ToolUse{}} = assigns) do
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
          ]}><%= @content.name %></code>
          <%= if @tool_results[@content.id] do %>
            <Lucideicons.check
              :if={@tool_results[@content.id].is_error == false}
              class="size-3 text-green-500" />
            <Lucideicons.circle_x
              :if={@tool_results[@content.id].is_error == true}
              class="size-4 text-red-500" />
          <% end %>
        </div>
      </:toggle>

      <div class="grid grid-cols-[auto_1fr] gap-x-2 gap-y-3 items-center">
        <div class="text-xs text-omni-text-2">Input:</div>
        <pre class={[
          "px-2 py-1 font-mono text-xs text-wrap rounded",
          "bg-omni-bg-2 text-omni-text-2"
        ]}><%= format_json(@content.input) %></pre>

        <%= if @tool_results[@content.id] do %>
          <div class="text-xs text-omni-text-2">Output:</div>
          <pre class={[
            "px-2 py-1 font-mono text-xs text-wrap rounded",
            "bg-omni-bg-2 text-omni-text-2",
            if(@tool_results[@content.id].is_error, do: "border border-red-500")
          ]}><%= format_tool_result(@tool_results[@content.id]) %></pre>
        <% end %>
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

  # ── UI primitives ───────────────────────────────────────────────

  @doc "Compact display of token counts and cost."
  attr :usage, Omni.Usage, required: true

  def usage_block(assigns) do
    ~H"""
    <div class={[
      "group inline-flex items-center gap-1.5 font-mono text-xs",
      "text-omni-text-3"
    ]}>
      <div>
        <Lucideicons.chart_no_axes_column class="size-4 text-blue-500" />
      </div>
      <div class="flex items-center gap-1.5">
        <div class="flex items-center gap-0.5">
          <Lucideicons.arrow_up class="size-3 text-omni-text-4" />
          <span>{format_token_count(@usage.input_tokens)}</span>
        </div>
        <div class="flex items-center gap-0.5">
          <Lucideicons.arrow_up class="size-3 rotate-180 text-omni-text-4" />
          <span>{format_token_count(@usage.output_tokens)}</span>
        </div>
        <div class="flex items-center gap-0.5">
          <span class="text-omni-text-4">$</span>
          <span>{format_token_cost(@usage.total_cost)}</span>
        </div>
      </div>
    </div>
    """
  end

  @doc "Prev/next navigation with position indicator (e.g. \"2/3\")."
  attr :version_id, :integer, required: true
  attr :versions, :list, required: true

  def version_nav(assigns) do
    idx = Enum.find_index(assigns.versions, &(&1 == assigns.version_id))

    assigns =
      assigns
      |> assign(:prev_id, if(idx > 0, do: Enum.at(assigns.versions, idx - 1)))
      |> assign(:next_id, Enum.at(assigns.versions, idx + 1))

    ~H"""
    <div class="flex items-center gap-0.5">
      <button
        class={[
          "transition-colors disabled:opacity-50 [:not(:disabled)]:cursor-pointer",
          "text-omni-text-4 [:not(:disabled)]:hover:text-omni-accent-1",
        ]}
        disabled={hd(@versions) == @version_id}
        phx-click={
          JS.dispatch("omni:before-update")
          |> JS.push("omni:navigate", value: %{node_id: @prev_id})
        }>
        <Lucideicons.chevron_down class="size-4 rotate-90" />
      </button>
      <span class="font-mono text-xs text-omni-text-3">{sibling_pos(@version_id, @versions)}</span>
      <button
        class={[
          "transition-colors disabled:opacity-50 [:not(:disabled)]:cursor-pointer",
          "text-omni-text-4 [:not(:disabled)]:hover:text-omni-accent-1",
        ]}
        disabled={List.last(@versions) == @version_id}
        phx-click={
          JS.dispatch("omni:before-update")
          |> JS.push("omni:navigate", value: %{node_id: @next_id})
        }>
        <Lucideicons.chevron_down class="size-4 -rotate-90" />
      </button>
    </div>
    """
  end

  @doc "Formatted time display with tooltip showing full date."
  attr :time, DateTime, required: true

  def timestamp(assigns) do
    ~H"""
    <div>
      <time
        class="text-xs text-omni-text-4"
        datetime={Calendar.strftime(@time, "%c")}
        title={Calendar.strftime(@time, "%c")}>
        {Calendar.strftime(@time, "%I:%M%P")}
      </time>
    </div>
    """
  end

  @doc """
  Collapsible section with an icon and optional toggle label.

  The `:icon` slot is shown when collapsed and replaced by a chevron on
  hover or when expanded. The `:toggle` slot overrides the text label.
  """
  attr :label, :string, default: nil
  slot :icon, required: true
  slot :toggle
  slot :inner_block, required: true

  def expandable(assigns) do
    ~H"""
    <div class="group/expandable">
      <div
        class="group/toggle inline-flex items-center gap-1.5 cursor-pointer"
        phx-click={JS.toggle_class("active", to: {:closest, ".group\\/expandable"})}>
        <div class="group-hover/toggle:hidden group-[.active]/expandable:hidden">
          {render_slot(@icon)}
        </div>
        <div class="hidden group-hover/toggle:block group-[.active]/expandable:block">
          <Lucideicons.chevron_down class={cls([
            "size-4 transition-all group-[.active]/expandable:rotate-180",
            "text-omni-text-4 group-hover/toggle:text-omni-text-3"
          ])} />
        </div>
        <div class={[
          "text-sm transition-colors",
          "text-omni-text-3 group-hover/toggle:text-omni-text-2"
        ]}>
          {render_slot(@toggle) || @label || "Expand"}
        </div>
      </div>

      <div class={[
        "ml-4 opacity-0 h-0 invisible overflow-hidden transition-all",
        "group-[.active]/expandable:opacity-100 group-[.active]/expandable:h-auto group-[.active]/expandable:visible"
      ]}>
        <div class="p-1.5">
          {render_slot(@inner_block)}
        </div>
      </div>
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
          event="omni:select_model" />
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
          prompt="Thinking" />
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

  @doc "Dropdown select with support for grouped options."
  attr :id, :string, required: true
  attr :options, :list, required: true
  attr :value, :string, default: nil
  attr :prompt, :string, default: "Select..."
  attr :event, :string, required: true
  attr :target, :any, default: nil

  def select(assigns) do
    assigns = assign(assigns, :selected_label, find_option_label(assigns.options, assigns.value))

    ~H"""
    <div
      id={@id}
      class="group/select relative inline-flex"
      phx-click-away={JS.remove_class("active", to: "##{@id}")}>
      <button
        type="button"
        class={[
          "inline-flex items-center gap-1.5 text-sm transition-colors cursor-pointer",
          "text-omni-text-3 hover:text-omni-accent-1"
        ]}
        phx-click={JS.toggle_class("active", to: "##{@id}")}>
        <span>{@selected_label || @prompt}</span>
        <Lucideicons.chevron_down class={cls([
          "size-3.5 transition-transform",
          "rotate-180 group-[.active]/select:rotate-0"
        ])} />
      </button>

      <div class={[
        "absolute bottom-full mb-4 z-20 -translate-x-4",
        "min-w-48 max-h-64 overflow-y-auto",
        "bg-omni-bg border border-omni-border-2 rounded-lg shadow-lg",
        "opacity-0 invisible scale-95 transition-all origin-bottom-left",
        "group-[.active]/select:opacity-100 group-[.active]/select:visible group-[.active]/select:scale-100"
      ]}>
        <.select_items
          :for={item <- @options}
          item={item}
          value={@value}
          event={@event}
          target={@target}
          select_id={@id} />
      </div>
    </div>
    """
  end

  defp select_items(%{item: %{options: options}} = assigns) do
    assigns = assign(assigns, :options, options)

    ~H"""
    <div class="px-3 py-1.5 text-xs text-omni-text-4 bg-omni-bg-2 font-medium uppercase tracking-wide">
      {@item.label}
    </div>
    <.select_option
      :for={option <- @options}
      option={option}
      value={@value}
      event={@event}
      target={@target}
      select_id={@select_id} />
    """
  end

  defp select_items(assigns) do
    ~H"""
    <.select_option
      option={@item}
      value={@value}
      event={@event}
      target={@target}
      select_id={@select_id} />
    """
  end

  defp select_option(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "block w-full text-left px-3 py-1.5 text-sm whitespace-nowrap transition-colors cursor-pointer",
        if(@option.value == @value,
          do: "text-omni-accent-1",
          else: "text-omni-text-2 hover:bg-omni-bg-1 hover:text-omni-accent-1"
        )
      ]}
      phx-click={
        JS.push(@event, value: %{value: @option.value})
        |> JS.remove_class("active", to: "##{@select_id}")
      }
      {if @target, do: [{"phx-target", @target}], else: []}>
      {@option.label}
    </button>
    """
  end

end
