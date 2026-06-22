defmodule Omni.UI.SessionsUI do
  @moduledoc """
  Function components for the sessions sidebar.

    * `session_list/1` — renders a list of session summaries as clickable rows
  """

  use Phoenix.Component
  alias Phoenix.LiveView.JS
  import Omni.UI.CoreUI, only: [timestamp: 1]

  @doc """
  Renders a list of session summaries as clickable rows.

  Each row fires `phx-click="switch_session"` with the session id in
  `phx-value-session-id` so the parent LiveView can route to it.

  Sessions whose `:status` is non-nil are flagged with a small indicator
  beside the title (`:busy` pulses, `:paused` is solid amber, `:idle` is
  a muted dot). Sessions without a status (i.e. not currently running)
  show no indicator.

  """
  attr :sessions, :list, required: true
  attr :current_id, :string, default: nil
  attr :empty_label, :string, default: "No sessions yet"
  attr :target, :any, required: true

  def session_list(assigns) do
    ~H"""
    <div>
      <p :if={@sessions == []} class="px-4 py-6 text-sm text-omni-text-3 text-center">
        {@empty_label}
      </p>

      <ul :if={@sessions != []} class="divide-y divide-omni-border-3">
        <li
          :for={session <- @sessions}
          class={session.id == @current_id && "bg-omni-accent-2/10"}>
          <div
            role="button"
            phx-click="open_session"
            phx-value-session-id={session.id}
            class="group w-full px-3 py-2 text-left cursor-pointer">

            <div class="flex items-center gap-2">
              <.rename_form session={session} target={@target} />
            </div>

            <div class="flex items-center gap-2">
              <div class="flex-1 flex items-center gap-2">
                <.session_status_icon status={Map.get(session, :status)} />
                <.timestamp
                  time={session.updated_at}
                  format="%-d %B" />
              </div>
              <.delete_actions session={session} target={@target} />
            </div>
          </div>
        </li>
      </ul>
    </div>
    """
  end

  attr :session, :map, required: true
  attr :target, :any, required: true

  defp rename_form(assigns) do
    ~H"""
    <form
      id={"rename-form-#{@session.id}"}
      phx-submit={
        JS.push("rename")
        |> JS.remove_class("editing", to: {:closest, ".group"})
      }
      phx-target={@target}
      phx-click={%JS{}}
      phx-stop-propagation="click"
      class="flex-1 min-w-0 hidden group-[.editing]:block">
      <input type="hidden" name="session_id" value={@session.id} />
      <input
        id={"rename-#{@session.id}"}
        type="text"
        name="title"
        value={@session.title || ""}
        autocomplete="off"
        phx-blur={
          JS.dispatch("submit", to: "#rename-form-#{@session.id}")
          |> JS.remove_class("editing", to: {:closest, ".group"})
        }
        phx-keydown={
          JS.dispatch("omni:reset", to: "#rename-#{@session.id}")
          |> JS.remove_class("editing", to: {:closest, ".group"})
        }
        phx-key="Escape"
        class="w-full p-0 text-sm bg-transparent border-b border-omni-accent-1 outline-none text-omni-text-1" />
    </form>
    <div class="flex-1 text-sm text-omni-text-1 group-hover:text-omni-accent-1 truncate group-[.editing]:hidden">
      {@session.title || "Untitled"}
    </div>
    <div class="shrink-0 overflow-hidden pointer-fine:w-0 pointer-fine:opacity-0 group-hover:w-auto group-hover:opacity-100 group-[.editing]:hidden">
      <button
        type="button"
        title="Rename session"
        phx-click={
          JS.add_class("editing", to: {:closest, ".group"})
          |> JS.dispatch("omni:select", to: "#rename-#{@session.id}")
        }
        phx-stop-propagation="click"
        class="flex items-center justify-center size-6 rounded cursor-pointer text-blue-500 hover:bg-blue-500/10 transition-colors">
        <Lucideicons.pencil class="size-4" />
      </button>
    </div>
    """
  end

  attr :session, :map, required: true
  attr :target, :any, required: true

  defp delete_actions(assigns) do
    ~H"""
    <div
      class={[
        "shrink-0 overflow-hidden pointer-fine:w-0 pointer-fine:opacity-0",
        "group-hover:w-auto group-hover:opacity-100",
        "[&:has(>.active)]:w-auto [&:has(>.active)]:opacity-100"
      ]}>
      <button
        type="button"
        title="Delete session"
        class={[
          "flex items-center justify-center size-6 rounded cursor-pointer text-red-500 hover:bg-red-500/10 transition-colors",
          "[&.active]:hidden"
        ]}
        phx-click={JS.transition("active", time: 5000)}
        phx-stop-propagation="click">
        <Lucideicons.trash_2 class="size-4" />
      </button>
      <button
        type="button"
        title="Confirm delete"
        class={[
          "flex items-center justify-center h-6 px-2 rounded cursor-pointer text-red-500 hover:bg-red-500/10 transition-colors",
          "hidden [.active+&]:block"
        ]}
        phx-click="delete"
        phx-value-id={@session.id}
        phx-target={@target}
        phx-stop-propagation="click">
        <span class="text-sm font-medium">Sure?</span>
      </button>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp session_status_icon(%{status: :busy} = assigns) do
    ~H"""
    <Lucideicons.loader_circle class="size-4 text-omni-accent-1 animate-spin" />
    """
  end

  defp session_status_icon(%{status: :idle} = assigns) do
    ~H"""
    <Lucideicons.circle class="size-4 text-omni-accent-2" />
    """
  end

  defp session_status_icon(%{status: :paused} = assigns) do
    ~H"""
    <Lucideicons.circle_pause class="size-4 text-amber-500" />
    """
  end

  defp session_status_icon(assigns) do
    ~H"""
    <Lucideicons.circle_dashed class="size-4 text-omni-text-4/50" />
    """
  end
end
