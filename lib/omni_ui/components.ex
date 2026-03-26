defmodule OmniUI.Components do
  use Phoenix.Component
  import OmniUI.Helpers
  alias OmniUI.Icons
  alias Phoenix.LiveView.JS

  slot :inner_block, required: true
  slot :current_turn

  slot :toolbar do
    attr :align, :string
  end

  slot :footer

  def chat_interface(assigns) do
    ~H"""
    <div class={[
      "omni-ui flex flex-col h-full [interpolate-size:allow-keywords]",
      "bg-omni-bg text-omni-text",
    ]}>
      <div class="flex-auto overflow-y-scroll">
        <div class="max-w-3xl mx-auto flex flex-col gap-16 px-12 py-16">
          {render_slot(@inner_block)}
          {render_slot(@current_turn)}
        </div>
      </div>

      <div class={["shrink-0", if(@footer == [], do: "pb-8", else: "pb-6")]}>
        <div class="max-w-3xl mx-auto flex flex-col items-center gap-6">
          <.live_component id="editor" module={OmniUI.MessageEditor}>
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

  attr :rest, :global
  slot :inner_block, required: true

  def message_list(assigns) do
    ~H"""
    <div class="flex flex-col gap-24" {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :turn, OmniUI.Turn, required: true
  attr :rest, :global

  def turn(assigns) do
    ~H"""
    <div class="flex flex-col gap-24" {@rest}>
      <div class="flex flex-col items-end gap-6">
        <.user_message
          text={@turn.user_text}
          attachments={@turn.user_attachments} />

        <.user_message_actions
          :if={@turn.status == :complete}
          turn_id={@turn.id}
          versions={@turn.edits}
          timestamp={@turn.user_timestamp} />
      </div>

      <div class="flex flex-col gap-6">
        <.assistant_message
          content={@turn.content}
          tool_results={@turn.tool_results}
          streaming={@turn.status == :streaming} />

        <.assistant_message_actions
          :if={@turn.status == :complete}
          turn_id={@turn.id}
          node_id={@turn.res_id}
          versions={@turn.regens}
          usage={@turn.usage} />
      </div>
    </div>
    """
  end

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

  attr :turn_id, :integer, required: true
  attr :versions, :list, required: true
  attr :timestamp, DateTime, required: true

  def user_message_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-4">
      <time
        class="text-xs text-omni-text-4"
        datetime={Calendar.strftime(@timestamp, "%c")}
        title={Calendar.strftime(@timestamp, "%c")}>
        {Calendar.strftime(@timestamp, "%I:%M%P")}
      </time>

      <button
        phx-click={
          JS.push("copy_message", value: %{turn_id: @turn_id, role: "user"})
          |> JS.add_class("success")
          |> JS.dispatch("omni-ui:copied")
        }
        class={[
          "group flex items-center gap-1.5 text-xs transition-colors cursor-pointer",
          "text-omni-text-3 hover:text-omni-accent-1"
        ]}>
        <Icons.copy class="size-3 group-[.success]:hidden" />
        <Icons.check class="size-3 hidden group-[.success]:block text-green-500" />
        <span class="group-[.success]:hidden">Copy</span>
        <span class="hidden group-[.success]:inline text-green-500">Copied!</span>
      </button>

      <button
        class={[
          "flex items-center gap-1.5 text-xs transition-colors cursor-pointer",
          "text-omni-text-3 hover:text-omni-accent-1"
        ]}>
        <Icons.rotate class="size-3" />
        <span>Edit</span>
      </button>

      <.version_nav
        :if={length(@versions) > 1}
        version_id={@turn_id}
        versions={@versions} />
    </div>
    """
  end

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
          tool_results={@tool_results} />
      </div>

      <!-- TODO - message error -->
    </div>
    """
  end

  attr :turn_id, :integer, required: true
  attr :node_id, :integer, required: true
  attr :versions, :list, required: true
  attr :usage, Omni.Usage, required: true

  def assistant_message_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-4">
      <button
        phx-click={
          JS.push("copy_message", value: %{turn_id: @turn_id, role: "assistant"})
          |> JS.add_class("success")
          |> JS.dispatch("omni-ui:copied")
        }
        class={[
          "group flex items-center gap-1.5 text-xs transition-colors cursor-pointer",
          "text-omni-text-3 hover:text-omni-accent-1"
        ]}>
        <Icons.copy class="size-3 group-[.success]:hidden" />
        <Icons.check class="size-3 hidden group-[.success]:block text-green-500" />
        <span class="group-[.success]:hidden">Copy</span>
        <span class="hidden group-[.success]:inline text-green-500">Copied!</span>
      </button>

      <button
        class={[
          "flex items-center gap-1.5 text-xs transition-colors cursor-pointer",
          "text-omni-text-3 hover:text-omni-accent-1"
        ]}>
        <Icons.rotate class="size-3" />
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

  attr :content, :map, required: true
  attr :tool_results, :map, default: %{}
  attr :streaming, :boolean, default: false

  def content_block(%{content: %Omni.Content.Text{}} = assigns) do
    ~H"""
    <.markdown text={@content.text} class="text-base" />
    """
  end

  def content_block(%{content: %Omni.Content.Thinking{}} = assigns) do
    ~H"""
    <.expandable label={if(@streaming, do: "Thinking", else: "Thought")}>
      <:icon>
        <Icons.sparkle
          class={[
            "size-4 text-amber-500",
            if(@streaming, do: "animate-spin")
          ]} />
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

  def content_block(%{content: %Omni.Content.ToolUse{}} = assigns) do
    ~H"""
    <.expandable>
      <:icon>
        <Icons.cog class={[
          "size-4",
          "text-omni-text-4",
          if(@streaming, do: "animate-spin")
        ]} />
      </:icon>

      <:toggle>
        <div class="flex items-center gap-1">
          <code class={[
            "px-2 py-1 rounded font-mono text-xs",
            "bg-omni-bg-1 text-omni-text-1"
          ]}><%= @content.name %></code>
          <%= if @tool_results[@content.id] do %>
            <Icons.check
              :if={@tool_results[@content.id].is_error == false}
              class="size-3 text-green-500" />
            <Icons.circle_x
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
          <Icons.paperclip class="size-4" />
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

  attr :usage, Omni.Usage, required: true

  def usage_block(assigns) do
    ~H"""
    <div class={[
      "group inline-flex items-center gap-1.5 font-mono text-xs",
      "text-omni-text-3"
    ]}>
      <div>
        <Icons.chart_no_axis class="size-4 text-blue-500" />
      </div>
      <div class="flex items-center gap-1.5">
        <div class="flex items-center gap-0.5">
          <Icons.arrow_up class="size-3 text-omni-text-4" />
          <span>{format_token_count(@usage.input_tokens)}</span>
        </div>
        <div class="flex items-center gap-0.5">
          <Icons.arrow_up class="size-3 rotate-180 text-omni-text-4" />
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

  attr :version_id, :integer, required: true
  attr :versions, :list, required: true

  def version_nav(assigns) do
    idx = Enum.find_index(assigns.versions, &(&1 == assigns.version_id))

    assigns =
      assigns
      |> assign(:prev_id, Enum.at(assigns.versions, idx - 1))
      |> assign(:next_id, Enum.at(assigns.versions, idx + 1))

    ~H"""
    <div class="flex items-center gap-0.5">
      <button
        class={[
          "transition-colors disabled:opacity-50 [:not(:disabled)]:cursor-pointer",
          "text-omni-text-4 [:not(:disabled)]:hover:text-omni-accent-1",
        ]}
        disabled={hd(@versions) == @version_id}
        phx-click={JS.push("navigate", value: %{node_id: @prev_id})}>
        <Icons.chevron_down class="size-4 rotate-90" />
      </button>
      <span class="font-mono text-xs text-omni-text-3">{sibling_pos(@version_id, @versions)}</span>
      <button
        class={[
          "transition-colors disabled:opacity-50 [:not(:disabled)]:cursor-pointer",
          "text-omni-text-4 [:not(:disabled)]:hover:text-omni-accent-1",
        ]}
        disabled={List.last(@versions) == @version_id}
        phx-click={JS.push("navigate", value: %{node_id: @next_id})}>
        <Icons.chevron_down class="size-4 -rotate-90" />
      </button>
    </div>
    """
  end

  attr :model_options, :list
  attr :model, Omni.Model
  attr :thinking_options, :list
  attr :thinking, :atom
  attr :usage, Omni.Usage

  def toolbar(assigns) do
    ~H"""
    <div class="flex flex-auto items-center gap-4">
      <div class={[
        "flex items-center gap-4",
        "before:content=[''] before:w-px before:h-3 before:bg-omni-border-2"
      ]}>
        <.select
          id="model-select"
          options={@model_options}
          value={model_key(@model)}
          event="select_model" />
      </div>

      <div class={[
        "flex items-center gap-4",
        "before:content=[''] before:w-px before:h-3 before:bg-omni-border-2"
      ]}>
        <.select
          :if={@model.reasoning}
          id="thinking-select"
          options={@thinking_options}
          value={to_string(@thinking)}
          event="select_thinking"
          prompt="Thinking" />
      </div>

      <div class="flex-auto flex items-center justify-end">
        <.usage_block usage={@usage} />
      </div>
    </div>
    """
  end

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
        <Icons.chevron_down class={[
          "size-3.5 transition-transform",
          "rotate-180 group-[.active]/select:rotate-0"
        ]} />
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

  defp find_option_label(options, value) do
    Enum.find_value(options, fn
      %{value: v, label: label} ->
        if(v == value, do: label)

      %{options: items} ->
        Enum.find_value(items, fn %{value: v, label: label} -> if(v == value, do: label) end)
    end)
  end

  attr :label, :string
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
          <Icons.chevron_down
            class={[
              "size-4 transition-all group-[.active]/expandable:rotate-180",
              "text-omni-text-4 group-hover/toggle:text-omni-text-3"
            ]} />
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

  attr :text, :string, required: true
  attr :rest, :global

  def markdown(assigns) do
    ~H"""
    <div class={[
      "leading-[1.5]",
      "[&>*:first-child]:mt-0! [&>*:last-child]:mb-0!",
      "[&_p,ul,ol,h1,h2,h3,h4,h5,h6]:mb-4 [&_p,ul,ol,h1,h2,h3,h4,h5,h6]:max-w-prose",
      "[&_h1,h2]:mt-12 [&_h3]:mt-6",
      "[&_h1,h2,h4,h5,h6]:font-bold [&_h3,h5]:italic",
      "[&_h1]:text-3xl [&_h1]:font-black",
      "[&_h2]:text-2xl [&_h2]:font-bold",
      "[&_h3]:text-xl [&_h3]:font-bold",
      "[&_h4]:text-lg [&_h4]:font-bold",
      "[&_h5]:font-bold",
      "[&_h6]:font-medium [&_h6]:italic",
      "[&_ul]:list-disc [&_ul]:pl-5",
      "[&_ol]:list-decimal [&_ol]:pl-5",
      "[&_li]:my-0.5",
      "[&_table,pre,img,hr]:my-6",
      "[&_table]:w-full [&_table]:table-fixed [&_table]:text-sm",
      "[&_table]:border [&_table]:border-separate [&_table]:border-spacing-0 [&_table]:rounded-xl",
      "[&_table]:border-omni-border-3",
      "[&_thead_th]:border-b [&_thead_th]:border-omni-border-3",
      "[&_th,td]:text-left [&_th,td]:p-2.5",
      "[&_tbody>tr]:odd:bg-omni-bg-2",
      "[&_pre]:-mx-6 [&_pre]:px-6 [&_pre]:py-5 [&_pre]:rounded-xl [&_pre]:overflow-y-scroll",
      "[&_hr]:h-px [&_hr]:bg-omni-border-2 [&_hr]:border-none",
      "[&_a]:font-medium [&_a]:hover:underline [&_a]:transition-colors",
      "[&_a]:text-omni-accent-1 [&_a]:hover:text-omni-accent-2",
      "[&_code]:text-sm [&_code]:leading-[1.625] [&_code]:font-mono",
      "[&_:not(pre)>code]:px-1 [&_:not(pre)>code]:py-0.5 [&_:not(pre)>code]:rounded-sm",
      "[&_:not(pre)>code]:bg-omni-bg-1",
      @rest.class
    ]}>
      <%= to_md(@text) %>
    </div>
    """
  end
end
