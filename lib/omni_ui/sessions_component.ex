defmodule OmniUI.SessionsComponent do
  @moduledoc """
  A LiveComponent that renders the sessions drawer.

  Slides in as an overlay over the main chat interface, lists the user's
  persisted sessions (most recent first), and offers click-to-switch and
  hover-to-delete actions.

  Fetches once on mount and again on subsequent mounts (i.e. each time the
  drawer is opened). No PubSub; closing and reopening the drawer is the
  refresh mechanism.

  ## Assigns from parent

    * `id` — required Phoenix component id
    * `current_id` — the currently active session id (for row highlighting)

  Calls `OmniUI.Store.list/1` and `OmniUI.Store.delete/2` directly —
  the configured adapter is resolved at the call site.

  ## Events bubbled to the parent LiveView (not `phx-target`-ed)

    * `switch_session` with `session-id` — parent should push_patch to the
      session URL
    * `close_sessions` — parent should close the drawer
    * `{OmniUI, :active_session_deleted}` — sent as a process message when
      the user deletes the currently active session
  """

  use Phoenix.LiveComponent

  alias OmniUI.{Components, Store}

  @page_size 50

  @impl true
  def render(assigns) do
    ~H"""
    <aside
      class="omni-ui h-full flex flex-col bg-omni-bg"
      phx-click-away="close_sessions"
      phx-window-keydown="close_sessions"
      phx-key="Escape">

      <header class="h-12 px-4 flex items-center justify-between border-b border-omni-border-3 shrink-0">
        <h2 class="text-sm font-medium text-omni-text-1">Sessions</h2>
        <button
          type="button"
          phx-click="close_sessions"
          title="Close"
          class="flex items-center justify-center size-8 rounded cursor-pointer text-omni-text-1 hover:text-omni-accent-1 hover:bg-omni-accent-2/10">
          <Lucideicons.x class="size-4" />
        </button>
      </header>

      <div class="flex-1 overflow-y-auto">
        <Components.session_list sessions={@sessions} current_id={@current_id}>
          <:actions :let={session}>
            <.row_actions session={session} confirming={@confirming_delete == session.id} target={@myself} />
          </:actions>
        </Components.session_list>

        <div :if={@has_more} class="p-3">
          <button
            type="button"
            phx-click="load_more"
            phx-target={@myself}
            class="w-full py-2 text-sm text-omni-text-2 hover:text-omni-accent-1 rounded hover:bg-omni-accent-2/10 cursor-pointer">
            Load more
          </button>
        </div>
      </div>
    </aside>
    """
  end

  attr :session, :map, required: true
  attr :confirming, :boolean, required: true
  attr :target, :any, required: true

  defp row_actions(%{confirming: true} = assigns) do
    ~H"""
    <div class="flex items-center gap-1 py-2">
      <button
        type="button"
        phx-click="delete"
        phx-value-id={@session.id}
        phx-target={@target}
        class="px-2 py-1 text-xs rounded bg-red-500/10 text-red-500 hover:bg-red-500/20 cursor-pointer">
        Delete
      </button>
      <button
        type="button"
        phx-click="cancel_delete"
        phx-target={@target}
        class="px-2 py-1 text-xs rounded text-omni-text-2 hover:bg-omni-accent-2/10 cursor-pointer">
        Cancel
      </button>
    </div>
    """
  end

  defp row_actions(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="confirm_delete"
      phx-value-id={@session.id}
      phx-target={@target}
      title="Delete session"
      class="flex items-center justify-center size-7 rounded cursor-pointer text-omni-text-3 hover:text-red-500 hover:bg-red-500/10 opacity-0 group-hover:opacity-100 focus:opacity-100 transition-opacity">
      <Lucideicons.trash_2 class="size-4" />
    </button>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       sessions: nil,
       loaded: 0,
       has_more: false,
       confirming_delete: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if socket.assigns.sessions == nil do
        load_page(socket, 0)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("load_more", _, socket) do
    {:noreply, load_page(socket, socket.assigns.loaded, append: true)}
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirming_delete, id)}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirming_delete, nil)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    :ok = Store.delete(id)

    if id == socket.assigns.current_id do
      send(self(), {OmniUI, :active_session_deleted})
    end

    sessions = Enum.reject(socket.assigns.sessions, &(&1.id == id))

    {:noreply,
     assign(socket,
       sessions: sessions,
       loaded: length(sessions),
       confirming_delete: nil
     )}
  end

  defp load_page(socket, offset, opts \\ []) do
    {:ok, page} = Store.list(limit: @page_size, offset: offset)

    sessions =
      if Keyword.get(opts, :append, false) do
        socket.assigns.sessions ++ page
      else
        page
      end

    assign(socket,
      sessions: sessions,
      loaded: length(sessions),
      has_more: length(page) == @page_size
    )
  end
end
