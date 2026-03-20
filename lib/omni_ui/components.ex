defmodule OmniUI.Components do
  use Phoenix.Component
  import OmniUI.Helpers
  alias OmniUI.Icons
  alias Phoenix.LiveView.JS

  attr :turns, Phoenix.LiveView.LiveStream, required: true
  attr :current_turn, OmniUI.Turn
  attr :usage, Omni.Usage, required: true

  def chat_interface(assigns) do
    ~H"""
    <div
      class={[
        "flex flex-col h-full [interpolate-size:allow-keywords]",
        "text-zinc-800 bg-white",
      ]}>
      <div class="flex-auto overflow-y-scroll">
        <div class="max-w-3xl mx-auto flex flex-col gap-16 px-12 py-16">
          <div class="flex flex-col gap-24" id="turns" phx-update="stream">
            <.turn
              :for={{dom_id, turn} <- @turns}
              id={dom_id}
              turn={turn} />
          </div>
          <.turn :if={@current_turn} turn={@current_turn} />
        </div>
      </div>

      <div class="shrink-0 pb-8">
        <div class="max-w-3xl mx-auto flex flex-col items-center gap-6">
          <.live_component id="editor" module={OmniUI.MessageEditor}>
            <:control class="text-sm">
              <div>model select</div>
            </:control>
            <:control class="text-sm">
              <div>thinking</div>
            </:control>
            <:control class="ml-auto before:content-none">
              <.usage_block usage={@usage} />
            </:control>
          </.live_component>

          <div class={["text-xs", "text-zinc-500"]}>
            <p>Boring footer here...</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :turn, OmniUI.Turn, required: true
  attr :rest, :global

  def turn(assigns) do
    ~H"""
    <div class="space-y-8" {@rest}>
      <div class="flex flex-col gap-24">
        <.user_message
          text={@turn.user_text}
          attachments={@turn.user_attachments}
          timestamp={@turn.user_timestamp} />
        <.assistant_message
          content={@turn.content}
          tool_results={@turn.tool_results}
          timestamp={@turn.timestamp}
          streaming={@turn.status == :streaming} />
      </div>

      <div :if={@turn.status == :complete} class="flex items-center gap-4">
        <.sibling_nav
          :if={length(@turn.siblings) > 1}
          sibling_id={@turn.id}
          siblings={@turn.siblings} />
        <button class={[
          "flex items-center gap-1.5 text-xs transition-colors cursor-pointer",
          "text-slate-500 hover:text-blue-600"
        ]}>
          <Icons.rotate class="size-3" />
          <span>Redo</span>
        </button>
        <button class={[
          "flex items-center gap-1.5 text-xs transition-colors cursor-pointer",
          "text-slate-500 hover:text-blue-600"
        ]}>
          <Icons.copy class="size-3" />
          <span>Copy</span>
        </button>
        <div class="flex-auto flex justify-end">
          <.usage_block usage={@turn.usage} />
        </div>
      </div>
    </div>
    """
  end

  attr :text, :list, required: true
  attr :attachments, :list, required: true
  attr :timestamp, DateTime

  def user_message(assigns) do
    ~H"""
    <div class="flex justify-end">
      <div class="relative px-4 py-2 text-zinc-700 bg-slate-100  rounded-xl">
        <div class="flex flex-col gap-4">
          <.content_block
            :for={content <- @text}
            content={content} />
        </div>
      </div>

      <div :if={@attachments != []} class="mt-3 flex flex-wrap gap-2">
        <!-- TODO - attachment_tile -->
      </div>
    </div>
    """
  end

  attr :content, :list, required: true
  attr :tool_results, :map, required: true
  attr :streaming, :boolean, required: true
  attr :timestamp, DateTime

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
            if(@streaming, do: "animate-spin", else: "")
          ]} />
      </:icon>

      <.markdown text={@content.text} class="text-sm text-slate-500 italic" />
    </.expandable>
    """
  end

  def content_block(%{content: %Omni.Content.ToolUse{}} = assigns) do
    ~H"""
    <.expandable>
      <:icon>
        <Icons.cog class={[
          "size-4 text-zinc-400",
          if(@streaming, do: "animate-spin", else: "")
        ]} />
      </:icon>

      <:toggle>
        <div class="flex items-center gap-1">
          <code
            class="font-mono text-xs text-slate-700 bg-slate-100 px-2 py-1 rounded"
          ><%= @content.name %></code>
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
        <div class="text-xs text-slate-600">Input:</div>
        <pre class="font-mono text-xs text-slate-600 bg-slate-50 /50 px-2 py-1 text-wrap rounded"><%= format_json(@content.input) %></pre>

        <%= if @tool_results[@content.id] do %>
          <div class="text-xs text-slate-600">Output:</div>
          <pre class={[
            "font-mono text-xs text-slate-600 bg-slate-50 /50 px-2 py-1 text-wrap rounded",
            if(@tool_results[@content.id].is_error, do: "border border-red-500")
          ]}><%= format_tool_result(@tool_results[@content.id]) %></pre>
        <% end %>
      </div>
    </.expandable>
    """
  end

  attr :usage, Omni.Usage, required: true

  def usage_block(assigns) do
    ~H"""
    <div class="group inline-flex items-center gap-1.5 font-mono text-xs text-slate-500">
      <div>
        <Icons.chart_no_axis class="size-4 text-blue-500" />
      </div>
      <div class="flex items-center gap-1.5">
        <div class="flex items-center gap-0.5">
          <Icons.arrow_up class="size-3 text-slate-400" />
          <span>{format_token_count(@usage.input_tokens)}</span>
        </div>
        <div class="flex items-center gap-0.5">
          <Icons.arrow_up class="size-3 text-slate-400 rotate-180" />
          <span>{format_token_count(@usage.output_tokens)}</span>
        </div>
        <div class="flex items-center gap-0.5">
          <span class="text-slate-400">$</span>
          <span>{format_token_cost(@usage.total_cost)}</span>
        </div>
      </div>
    </div>
    """
  end

  attr :sibling_id, :integer, required: true
  attr :siblings, :list, required: true

  def sibling_nav(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5">
      <button
        class={[
          if(hd(@siblings) == @sibling_id,
            do: "text-slate-300",
            else: "text-slate-400 hover:text-blue-500 transition-colors cursor-pointer")
        ]}>
        <Icons.chevron_down class="size-4 rotate-90" />
      </button>
      <span class="font-mono text-xs text-slate-500">{sibling_pos(@sibling_id, @siblings)}</span>
      <button
        class={[
          if(List.last(@siblings) == @sibling_id,
            do: "text-slate-300",
            else: "text-slate-400 hover:text-blue-500 transition-colors cursor-pointer")
        ]}>
        <Icons.chevron_down class="size-4 -rotate-90" />
      </button>
    </div>
    """
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
              "size-4 text-slate-400 transition-all",
              "group-hover/toggle:text-slate-500 group-hover/toggle group-[.active]/expandable:rotate-180"
            ]} />
        </div>
        <div class="text-sm transition-colors text-slate-500 group-hover/toggle:text-slate-600 group-hover/toggle">
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
      "[&_table]:border [&_table]:border-separate [&_table]:border-spacing-0 [&_table]:border-slate-200 [&_table]:rounded-xl",
      "[&_thead_th]:border-b [&_thead_th]:border-slate-200",
      "[&_th,td]:text-left [&_th,td]:p-2.5",
      "[&_tbody>tr]:odd:bg-slate-50",
      "[&_pre]:-mx-6 [&_pre]:px-6 [&_pre]:py-5 [&_pre]:rounded-xl [&_pre]:overflow-y-scroll",
      "[&_hr]:h-px [&_hr]:bg-slate-300 [&_hr]:border-none",
      "[&_a]:font-medium [&_a]:text-blue-500 [&_a]:hover:text-blue-400 [&_a]:hover:underline [&_a]:transition-colors",
      "[&_code]:text-sm [&_code]:leading-[1.625] [&_code]:font-mono",
      "[&_:not(pre)>code]:px-1 [&_:not(pre)>code]:py-0.5 [&_:not(pre)>code]:bg-slate-100 [&_:not(pre)>code]:rounded-sm",
      @rest.class
    ]}>
      <%= to_md(@text) %>
    </div>
    """
  end
end
