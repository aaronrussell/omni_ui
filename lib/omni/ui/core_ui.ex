defmodule Omni.UI.CoreUI do
  @moduledoc """
  Shared UI primitives used across the Omni.UI component kit.

  Imported automatically by `use Omni.UI`. These are general-purpose
  layout and control components (panels, selects, notifications) used by
  both the chat pipeline and the surrounding chrome (sessions sidebar,
  files panel).
  """

  use Phoenix.Component
  import Omni.UI.Helpers
  import Omni.Util, only: [maybe_put: 3]
  alias Phoenix.LiveView.JS

  # ── Panels ─────────────────────────────────────────────────────

  @doc """
  Flex column layout with a header and scrollable body.

  When the `:header` slot is provided it replaces the default
  `panel_header/1`. Used by `AgentLive`, `SessionsComponent`, and
  `FilesComponent` as the top-level section wrapper.
  """
  attr :title, :string, default: ""
  attr :body_class, :string, default: nil
  slot :header, required: false

  def panel(assigns) do
    ~H"""
    <div class="flex-auto flex flex-col h-full">
      <%= if @header != [] do %>
        {render_slot(@header)}
      <% else %>
        <.panel_header title={@title} />
      <% end %>

      <div class={["flex-1 min-h-0", @body_class]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Three-column header bar with a title and optional left/right action slots.

  The `:align` attr controls title placement — `"center"` (default) uses a
  three-column grid so the title stays centered regardless of slot widths;
  `"left"` or `"right"` collapses to a two-column flow.
  """
  attr :title, :string, required: true
  attr :align, :string, values: ~w(left center right), default: "center"
  slot :left, required: false
  slot :right, required: false

  def panel_header(assigns) do
    ~H"""
    <header class={[
      "grid items-center gap-4 h-12 px-4 border-b border-omni-border-3",
      if(@align == "center", do: "grid-cols-[1fr_auto_1fr]", else: "grid-cols-[auto_1fr_auto]")
    ]}>
      <%= if @left != [] do %>
        <div class="flex items-center gap-1">
          {render_slot(@left)}
        </div>
      <% end %>

      <div class={[
        if(@align == "center", do: "col-start-2"),
        if(@left == [] and @right != [], do: "col-span-2"),
        if(@left != [] and @right == [], do: "col-span-2"),
        "text-#{@align}"
      ]}>
        <span class="text-sm font-medium text-omni-text-1 text-nowrap truncate">
          {@title}
        </span>
      </div>

      <%= if @right != [] do %>
        <div class="flex items-center justify-end gap-1">
          {render_slot(@right)}
        </div>
      <% end %>
    </header>
    """
  end

  # ── Expandable ─────────────────────────────────────────────────

  @doc """
  Collapsible section with an icon and optional toggle label.
  """
  attr :label, :string,
    default: nil,
    doc: "text shown as the toggle label when no `:toggle` slot is given"

  slot :icon,
    required: true,
    doc: "shown when collapsed; replaced by a chevron on hover or when expanded"

  slot :toggle, doc: "content shown as the clickable toggle; overrides `:label`"

  slot :status

  slot :aside,
    doc: "optional content rendered alongside the header, outside the click target"

  slot :inner_block, required: true, doc: "the expanded body"

  def expandable(assigns) do
    ~H"""
    <div class="group/expandable">
      <div class="flex items-center justify-between gap-4">
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
          <div :if={@status != []}>{render_slot @status}</div>
        </div>

        <div :if={@aside != []}>{render_slot @aside}</div>
      </div>

      <div class={[
        "opacity-0 h-0 invisible overflow-hidden transition-all",
        "group-[.active]/expandable:opacity-100 group-[.active]/expandable:h-auto group-[.active]/expandable:visible"
      ]}>
        <div class="my-2 px-5.5 py-4 bg-omni-bg-2 border border-omni-border-3 rounded">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  # ── Select ─────────────────────────────────────────────────────

  @doc "Dropdown select with support for grouped options."
  attr :id, :string, required: true
  attr :options, :list, required: true
  attr :value, :string, default: nil
  attr :prompt, :string, default: "Select..."
  attr :name, :string, default: nil
  attr :event, :string, required: true
  attr :target, :any, default: nil
  attr :position, :string, default: "below", values: ~w(above below)

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
          if(@position == "above",
            do: "rotate-180 group-[.active]/select:rotate-0",
            else: "group-[.active]/select:rotate-180"
          )
        ])} />
      </button>

      <div class={[
        "absolute z-20 -translate-x-4",
        if(@position == "above",
          do: "bottom-full mb-4 origin-bottom-left",
          else: "top-full mt-4 origin-top-left"
        ),
        "min-w-48 max-h-64 overflow-y-auto",
        "bg-omni-bg border border-omni-border-2 rounded-lg shadow-lg",
        "opacity-0 invisible scale-95 transition-all",
        "group-[.active]/select:opacity-100 group-[.active]/select:visible group-[.active]/select:scale-100"
      ]}>
        <.select_items
          :for={item <- @options}
          item={item}
          value={@value}
          name={@name}
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
      name={@name}
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
      name={@name}
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
        JS.push(@event, value: maybe_put(%{value: @option.value}, :name, @name))
        |> JS.remove_class("active", to: "##{@select_id}")
      }
      {if @target, do: [{"phx-target", @target}], else: []}>
      {@option.label}
    </button>
    """
  end

  # ── Version nav ────────────────────────────────────────────────

  @doc "Prev/next navigation with position indicator (e.g. \"2/3\")."
  attr :version_id, :integer, required: true
  attr :versions, :list, required: true

  def version_nav(assigns) do
    idx = Enum.find_index(assigns.versions, &(&1 == assigns.version_id)) || -1

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

  # ── Timestamp ──────────────────────────────────────────────────

  @doc "Formatted time display with tooltip showing full date."
  attr :time, DateTime, required: true
  attr :format, :string, default: "%Y-%m-%d %H:%M"

  def timestamp(assigns) do
    ~H"""
    <time
      class="text-xs text-omni-text-4"
      datetime={Calendar.strftime(@time, "%c")}
      title={Calendar.strftime(@time, "%c")}>
      {time_ago(@time, @format)}
    </time>
    """
  end

  # ── Usage block ────────────────────────────────────────────────

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
          <Lucideicons.arrow_down class="size-3 text-omni-text-4" />
          <span>{format_token_count(@usage.output_tokens)}</span>
        </div>
        <div class="flex items-center gap-0.5">
          <Lucideicons.dollar_sign class="size-3 text-omni-text-4" />
          <span>{format_token_cost(@usage.total_cost)}</span>
        </div>
      </div>
    </div>
    """
  end

  # ── Notifications ──────────────────────────────────────────────

  @doc """
  Stacked toaster for in-app notifications.

  Renders the LiveView's `@streams.notifications` stream as a fixed-position
  stack in the bottom-right corner. Notifications are pushed via `Omni.UI.notify/2,3`
  and dismissed either manually (X button) or automatically after their timeout.
  """
  attr :stream, :any, required: true, doc: "the @streams.notifications assign"

  def notifications(assigns) do
    ~H"""
    <div
      id="omni-notifications"
      class="fixed top-16 right-4 z-50 flex flex-col gap-2 pointer-events-none"
      phx-update="stream">
      <div
        :for={{dom_id, n} <- @stream}
        id={dom_id}
        class={[
          "flex items-center gap-2.5 min-w-64 max-w-96 px-3 py-2.5 shadow-lg pointer-events-auto",
          "bg-omni-bg border border-l-4",
          notification_border_class(n.level)
        ]}>
        <.notification_icon level={n.level} />
        <div class="flex-1 pr-1.5 text-sm text-omni-text-1">{n.message}</div>
        <button
          type="button"
          class={[
            "flex items-center justify-center size-6 rounded cursor-pointer",
            "text-omni-text-1 hover:text-omni-accent-1 hover:bg-omni-accent-2/10"
          ]}
          phx-click="omni:dismiss"
          phx-value-id={n.id}>
          <Lucideicons.x class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  defp notification_border_class(:info), do: "border-omni-border-2"
  defp notification_border_class(:success), do: "border-green-500/50"
  defp notification_border_class(:warning), do: "border-amber-500/50"
  defp notification_border_class(:error), do: "border-red-500/50"

  attr :level, :atom, required: true

  defp notification_icon(%{level: :info} = assigns) do
    ~H"""
    <Lucideicons.info class="size-4 shrink-0 text-blue-500" />
    """
  end

  defp notification_icon(%{level: :success} = assigns) do
    ~H"""
    <Lucideicons.circle_check class="size-4 shrink-0 text-green-500" />
    """
  end

  defp notification_icon(%{level: :warning} = assigns) do
    ~H"""
    <Lucideicons.triangle_alert class="size-4 shrink-0 text-amber-500" />
    """
  end

  defp notification_icon(%{level: :error} = assigns) do
    ~H"""
    <Lucideicons.circle_x class="size-4 shrink-0 text-red-500" />
    """
  end
end
