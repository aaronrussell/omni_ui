defmodule Omni.UI.ChatUI do
  @moduledoc """
  Function components for the chat rendering pipeline.

  Imported automatically by `use Omni.UI`. Components are designed to
  compose within a `chat_interface/1` root, which provides the scroll
  container, editor area, and markdown typography styles. All components
  use the semantic OKLCH color tokens defined in `priv/static/omni_ui.css`.
  """

  use Phoenix.Component
  import Omni.UI.CoreUI
  import Omni.UI.Helpers
  alias Phoenix.LiveView.JS

  # ── Layout ──────────────────────────────────────────────────────

  @doc """
  Root layout for the chat interface.

  Provides the scroll container, markdown typography styles, and an optional
  editor. All other components are designed to be rendered within this root.

  When the `:editor` slot is not provided, renders a plain `EditorComponent`
  (textarea and attach button, no controls). When `:editor` is provided,
  renders the slot content instead — typically via `editor/1`.
  """
  slot :inner_block, required: true
  slot :editor
  slot :footer

  def chat_interface(assigns) do
    ~H"""
    <div
      class={[
        "omni-ui flex flex-col h-full @container/chat",
        "[interpolate-size:allow-keywords]",
        "bg-omni-bg text-omni-text"
        | md_styles()
      ]}>
      <div
        id="omni-view"
        class={[
          "flex-auto overflow-y-scroll",
          "px-4 py-8 @md/chat:px-8 @md/chat:py-16 @lg/chat:px-12"
        ]}>
        <div
          id="omni-content"
          class={[
            "max-w-2xl mx-auto flex flex-col gap-12 @md/chat:gap-12 @lg/chat:gap-24",
            "min-h-[var(--scroll-lock,auto)]"
          ]}>
          {render_slot(@inner_block)}
          <div id="omni-sentinel" class="h-0" />
        </div>
      </div>

      <div class={["shrink-0 px-12", if(@footer == [], do: "pb-8", else: "pb-6")]}>
        <div class="max-w-3xl mx-auto flex flex-col items-center gap-6">
          <%= if @editor != [] do %>
            {render_slot(@editor)}
          <% else %>
            <.live_component id="editor" module={Omni.UI.EditorComponent} />
          <% end %>

          <div
            :if={@footer != []}
            class={[
              "text-xs text-omni-text-4",
              "[&_a]:text-omni-text-3 [&_a]:underline [&_a]:transition-colors",
              "[&_a]:hover:text-omni-accent-2"
            ]}>
            {render_slot(@footer)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Editor ──────────────────────────────────────────────────────

  @doc """
  Editor component with optional controls.

  Wraps `EditorComponent` and provides default controls (model selector,
  thinking toggle, usage summary) when the relevant attrs are provided.
  All attrs are optional — when omitted, the editor renders with just the
  textarea and attach button.

  Three usage tiers:

      <%!-- Default editor + default controls: --%>
      <.editor model={@model} model_options={@model_options}
               thinking={@thinking} usage={@usage} />

      <%!-- Default editor + custom controls: --%>
      <.editor>
        <:controls><.my_controls /></:controls>
      </.editor>

      <%!-- No controls (just textarea): --%>
      <.editor />

  For a fully custom editor, skip `editor/1` entirely and render your own
  component inside `chat_interface`'s `:editor` slot.
  """
  attr :model_options, :list, default: nil
  attr :model, Omni.Model, default: nil
  attr :thinking, :atom, default: nil
  attr :usage, Omni.Usage, default: nil
  slot :controls

  @thinking_levels [:max, :high, :medium, :low, false]

  def editor(assigns) do
    assigns =
      assigns
      |> assign_new(:formatted_model_options, fn ->
        format_model_options(assigns.model_options)
      end)
      |> assign_new(:formatted_thinking_options, fn -> format_thinking_options() end)

    ~H"""
    <.live_component id="editor" module={Omni.UI.EditorComponent}>
      <:controls>
        <%= if @controls != [] do %>
          {render_slot(@controls)}
        <% else %>
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
                event="omni:select" name="model"
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
                event="omni:select" name="thinking"
                prompt="Thinking"
                position="above" />
            </div>

            <div :if={@usage} class="flex-auto flex items-center justify-end">
              <.usage_block usage={@usage} />
            </div>
          </div>
        <% end %>
      </:controls>
    </.live_component>
    """
  end

  defp format_thinking_options do
    Enum.map(@thinking_levels, fn val ->
      value = to_string(val)
      label = if val == false, do: "Off", else: String.capitalize(value)
      %{value: value, label: label}
    end)
  end

  # ── Turns ──────────────────────────────────────────────────────

  @doc """
  Stream container for committed turns.

  Iterates over a LiveView stream of `Omni.UI.Turn` structs, rendering each
  as a `TurnComponent`. When `:user` or `:assistant` slots are provided,
  they are threaded through to each `TurnComponent` (and from there to
  `turn/1`), allowing per-turn customisation while retaining the default
  rendering pipeline.

  Both slots expose the turn via `:let`.
  """
  attr :stream, :any, required: true
  attr :tool_components, :map, default: %{}
  attr :id, :string, default: "turns"
  slot :user
  slot :assistant

  def turn_list(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col gap-12 @md/chat:gap-12 @lg/chat:gap-24 empty:hidden" phx-update="stream">
      <div :for={{dom_id, turn} <- @stream} id={dom_id}>
        <.live_component
          module={Omni.UI.TurnComponent}
          id={"turn-#{turn.id}"}
          turn={turn}
          tool_components={@tool_components}>
          <:user :for={item <- @user} :let={turn}>
            {render_slot(item, turn)}
          </:user>
          <:assistant :for={item <- @assistant} :let={turn}>
            {render_slot(item, turn)}
          </:assistant>
        </.live_component>
      </div>
    </div>
    """
  end

  @doc """
  Renders a conversation turn with data-driven defaults.

  When `:user` or `:assistant` slots are provided, they override the default
  rendering for that zone. Both slots expose the turn via `:let`.

  When slots are omitted, defaults are rendered based on `@turn.status`:

    * **User** — `user_message/1` always, plus `user_message_actions/1` for
      completed turns or `timestamp/1` for streaming turns.
    * **Assistant** — `assistant_message/1` when content exists,
      `busy_block/1` when streaming, `assistant_message_actions/1` when complete.
  """
  attr :turn, Omni.UI.Turn, required: true
  attr :tool_components, :map, default: %{}
  attr :target, :any, default: nil
  slot :user
  slot :assistant

  def turn(assigns) do
    ~H"""
    <div class="flex flex-col gap-12 @md/chat:gap-12 @lg/chat:gap-24">
      <div class="flex flex-col items-end gap-6">
        <%= if @user != [] do %>
          {render_slot(@user, @turn)}
        <% else %>
          <.user_message text={@turn.user_text} attachments={@turn.user_attachments} />
          <%= if @turn.status == :complete do %>
            <.user_message_actions
              turn_id={@turn.id}
              versions={@turn.edits}
              timestamp={@turn.user_timestamp}
              target={@target} />
          <% else %>
            <.timestamp time={@turn.user_timestamp} />
          <% end %>
        <% end %>
      </div>
      <div
        :if={@assistant != [] or show_assistant?(@turn)}
        class="flex flex-col gap-6">
        <%= if @assistant != [] do %>
          {render_slot(@assistant, @turn)}
        <% else %>
          <.assistant_message
            :if={@turn.content != []}
            content={@turn.content}
            tool_results={@turn.tool_results}
            tool_components={@tool_components}
            streaming={@turn.status == :streaming} />
          <.assistant_message_actions
            :if={@turn.status == :complete}
            turn_id={@turn.id}
            node_id={@turn.res_id}
            versions={@turn.regens}
            usage={@turn.usage}
            target={@target} />
          <.busy_block
            :if={@turn.status == :streaming and show_busy?(@turn.content)} />
          <.error_block
            :if={@turn.status == :error}
            error={@turn.error} />
        <% end %>
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
        time={@timestamp}
        format="%-d %B" />

      <button
        phx-click={
          JS.push("copy", value: %{role: "user"}, target: @target)
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
    assigns = assign(assigns, :last_idx, length(assigns.content) - 1)

    ~H"""
    <div>
      <div class="flex flex-col gap-4">
        <.content_block
          :for={{content, idx} <- Enum.with_index(@content)}
          content={content}
          tool_results={@tool_results}
          tool_components={@tool_components}
          streaming={@streaming and idx == @last_idx} />
      </div>
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
          JS.push("copy", value: %{role: "assistant"}, target: @target)
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

  @doc "Standalone busy indicator shown after the last text block in a streaming turn."
  def busy_block(assigns) do
    ~H"""
    <div class="inline-flex items-center gap-1.5">
      <Lucideicons.bot class="size-4 text-blue-500" />
      <div class="flex items-baseline gap-2">
        <div class="text-sm text-omni-text-3">Working</div>
        <.busy_anim />
      </div>
    </div>
    """
  end

  attr :error, :string, required: true

  defp error_block(assigns) do
    ~H"""
    <div class="flex items-center gap-3 mb-4 px-4 py-3 text-red-600 bg-omni-bg-2 border border-red-500 rounded">
      <Lucideicons.triangle_alert class="size-4" />
      <p class="flex-1 text-sm">{@error}</p>
      <button
        class={[
          "inline-flex items-center gap-1.5 p-1.5 rounded text-sm border transition-colors cursor-pointer",
          "text-omni-text-1 bg-omni-bg border-omni-border-3 hover:bg-omni-accent-2/5 hover:border-omni-accent-2"
        ]}
        phx-click="omni:retry">
        <Lucideicons.rotate_cw class="size-3" />
        <span class="text-xs">Retry</span>
      </button>
    </div>
    """
  end

  @doc "Bouncing dots animation used inline within tool and thinking blocks."
  def busy_anim(assigns) do
    ~H"""
    <div class="flex items-center gap-1 text-omni-text-4">
      <div class="size-1.5 rounded-full bg-current animate-(--busy-animation)"></div>
      <div class="size-1.5 rounded-full bg-current animate-(--busy-animation) [animation-delay:0.2s]"></div>
      <div class="size-1.5 rounded-full bg-current animate-(--busy-animation) [animation-delay:0.4s]"></div>
      <div class="size-1.5 rounded-full bg-current animate-(--busy-animation) [animation-delay:0.6s]"></div>
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
        <Lucideicons.sparkle class="size-4 text-amber-500" />
      </:icon>
      <:status :if={@streaming}>
        <.busy_anim />
      </:status>

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
    tool_use_assigns =
      assign(%{__changed__: %{}},
        tool_use: tool_use,
        tool_result: assigns.tool_results[tool_use.id],
        streaming: assigns.streaming
      )

    case assigns.tool_components[tool_use.name] do
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
  attr :tool_use, Omni.Content.ToolUse, required: true
  attr :tool_result, Omni.Content.ToolResult, default: nil
  attr :streaming, :boolean, default: false

  slot :aside,
    doc: "content rendered alongside the header, outside the expandable's click target"

  def tool_use(assigns) do
    ~H"""
    <.expandable>
      <:icon>
        <Lucideicons.cog class="size-4 text-omni-text-4" />
      </:icon>

      <:toggle>
        <code class={[
          "px-2 py-1 rounded font-mono text-xs",
          "bg-omni-bg-1 text-omni-text-1"
        ]}><%= @tool_use.name %></code>
      </:toggle>

      <:status :if={@streaming}>
        <.busy_anim />
      </:status>

      <:status :if={not @streaming and @tool_result}>
        <Lucideicons.check
          :if={not @tool_result.is_error}
          class="size-3 text-green-500" />
        <Lucideicons.circle_x
          :if={@tool_result.is_error}
          class="size-4 text-red-500" />
      </:status>

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
  slot :image
  slot :action

  def attachment(assigns) do
    ~H"""
    <div class="relative group">
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

  Rendering is handled by `Omni.UI.Helpers.to_md/2`. Typography styles are
  applied via descendant selectors on `chat_interface/1` targeting the `.md`
  class — see `@markdown_styles`.
  """
  attr :text, :string, required: true
  attr :streaming, :boolean, default: false
  attr :rest, :global

  def markdown(assigns) do
    ~H"""
    <div class={["mdex leading-[1.5]"]} {@rest}>
      <%= to_md(@text, streaming: @streaming) %>
    </div>
    """
  end

  defp show_assistant?(%{status: :streaming}), do: true
  defp show_assistant?(%{status: :error}), do: true
  defp show_assistant?(%{content: [_ | _]}), do: true
  defp show_assistant?(_), do: false

  defp show_busy?([]), do: true
  defp show_busy?(content), do: match?(%Omni.Content.Text{}, List.last(content))
end
