defmodule OmniUI.SessionsUI do
  @moduledoc """
  Function components for the sessions sidebar.

    * `session_list/1` — renders a list of session summaries as clickable rows
  """

  use Phoenix.Component
  import OmniUI.CoreUI, only: [timestamp: 1]

  @doc """
  Renders a list of session summaries as clickable rows.

  Each row fires `phx-click="switch_session"` with the session id in
  `phx-value-session-id` so the parent LiveView can route to it.

  Sessions whose `:status` is non-nil are flagged with a small indicator
  beside the title (`:busy` pulses, `:paused` is solid amber, `:idle` is
  a muted dot). Sessions without a status (i.e. not currently running)
  show no indicator.

  The `:actions` slot renders per-row controls (e.g. delete) revealed
  on hover, and receives the session as its argument.
  """
  attr :sessions, :list, required: true
  attr :current_id, :string, default: nil
  attr :empty_label, :string, default: "No sessions yet"

  slot :actions,
    doc: "per-row action controls; receives the session map as the argument"

  def session_list(assigns) do
    ~H"""
    <div>
      <p :if={@sessions == []} class="px-4 py-6 text-sm text-omni-text-3 text-center">
        {@empty_label}
      </p>

      <ul :if={@sessions != []} class="divide-y divide-omni-border-3">
        <li
          :for={session <- @sessions}
          class={[
            "group flex items-center gap-2 px-3",
            session.id == @current_id && "bg-omni-accent-2/10"
          ]}>
          <button
            type="button"
            phx-click="switch_session"
            phx-value-session-id={session.id}
            class="flex-1 min-w-0 py-3 text-left cursor-pointer">
            <div class="flex items-center gap-2 min-w-0">
              <.session_status_dot status={Map.get(session, :status)} />
              <div class="text-sm text-omni-text-1 truncate">
                {session.title || "Untitled"}
              </div>
            </div>
            <.timestamp
              time={session.updated_at}
              format="%-d %B" />
          </button>

          <div :if={@actions != []} class="shrink-0">
            {render_slot(@actions, session)}
          </div>
        </li>
      </ul>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp session_status_dot(%{status: :busy} = assigns) do
    ~H"""
    <span
      title="Streaming"
      class="shrink-0 inline-block size-2 rounded-full bg-omni-accent-1 animate-pulse" />
    """
  end

  defp session_status_dot(%{status: :paused} = assigns) do
    ~H"""
    <span
      title="Awaiting input"
      class="shrink-0 inline-block size-2 rounded-full bg-amber-500" />
    """
  end

  defp session_status_dot(%{status: :idle} = assigns) do
    ~H"""
    <span title="Open" class="shrink-0 inline-block size-2 rounded-full bg-omni-text-4/50" />
    """
  end

  defp session_status_dot(assigns), do: ~H""
end
