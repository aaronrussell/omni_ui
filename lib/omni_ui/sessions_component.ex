defmodule OmniUI.SessionsComponent do
  @moduledoc """
  A LiveComponent that renders the sessions sidebar.

  Permanently mounted as a left sidebar over the main chat interface.
  Lists every persisted session plus any currently-running session that
  hasn't been persisted yet, with running sessions sorted to the top.
  Updates live in response to `Omni.Session.Manager` events.

  ## Assigns from parent

    * `id` — required Phoenix component id
    * `current_id` — the currently active session id (for row highlighting)
    * `manager` — the `Omni.Session.Manager` module to query

  ## Live updates

  Manager events are not delivered to LiveComponents directly — the parent
  LiveView receives `{:manager, _, _, _}` messages and forwards them with
  `send_update/2`, passing the event under a `manager_event:` assign that
  this component pattern-matches:

      def handle_info({:manager, _, _, _} = msg, socket) do
        send_update(OmniUI.SessionsComponent, id: "sessions", manager_event: msg)
        {:noreply, socket}
      end

  ## Events bubbled to the parent LiveView (not `phx-target`-ed)

    * `switch_session` with `session-id` — parent should `push_patch` to the
      session URL
    * `new_session` — parent should `push_patch` to `/`
    * `{OmniUI, :active_session_deleted}` — sent as a process message when
      the user deletes the currently active session
  """

  use Phoenix.LiveComponent

  alias OmniUI.Components

  @impl true
  def render(assigns) do
    ~H"""
    <aside class="omni-ui h-full flex flex-col bg-omni-bg">
      <header class="h-12 px-4 flex items-center justify-between border-b border-omni-border-3 shrink-0">
        <h2 class="text-sm font-medium text-omni-text-1">Sessions</h2>
        <button
          type="button"
          phx-click="new_session"
          title="New session"
          class="flex items-center justify-center size-8 rounded cursor-pointer text-omni-text-1 hover:text-omni-accent-1 hover:bg-omni-accent-2/10">
          <Lucideicons.plus class="size-4" />
        </button>
      </header>

      <div class="flex-1 overflow-y-auto">
        <Components.session_list sessions={@sessions} current_id={@current_id}>
          <:actions :let={session}>
            <.row_actions session={session} confirming={@confirming_delete == session.id} target={@myself} />
          </:actions>
        </Components.session_list>
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
    {:ok, assign(socket, sessions: nil, confirming_delete: nil)}
  end

  @impl true
  def update(%{manager_event: event}, socket) do
    sessions = apply_event(event, socket.assigns.sessions)
    {:ok, assign(socket, :sessions, sessions)}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if socket.assigns.sessions == nil do
        assign(socket, :sessions, load_sessions(socket.assigns.manager))
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirming_delete, id)}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirming_delete, nil)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    :ok = socket.assigns.manager.delete(id)

    if id == socket.assigns.current_id do
      send(self(), {OmniUI, :active_session_deleted})
    end

    sessions = Enum.reject(socket.assigns.sessions, &(&1.id == id))

    {:noreply,
     assign(socket,
       sessions: sessions,
       confirming_delete: nil
     )}
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp load_sessions(manager) do
    {:ok, persisted} = manager.list()
    open = manager.list_open()
    merge(persisted, open) |> sort()
  end

  defp merge(persisted, open) do
    persisted_by_id = Map.new(persisted, &{&1.id, &1})
    open_by_id = Map.new(open, &{&1.id, &1})

    ids = MapSet.union(MapSet.new(Map.keys(persisted_by_id)), MapSet.new(Map.keys(open_by_id)))
    now = DateTime.utc_now()

    Enum.map(ids, fn id ->
      build_entry(id, Map.get(persisted_by_id, id), Map.get(open_by_id, id), now)
    end)
  end

  defp build_entry(id, persisted, open, now) do
    %{
      id: id,
      title: (open && open.title) || (persisted && persisted.title),
      status: open && open.status,
      pid: open && open.pid,
      updated_at: (persisted && persisted.updated_at) || now,
      persisted?: not is_nil(persisted)
    }
  end

  # Open sessions sort to the top, then by updated_at descending. The
  # nil-status comparison sorts false (open) before true (closed) under
  # ascending sort_by, and DateTime.compare lets us compare directly.
  defp sort(sessions) do
    Enum.sort(sessions, fn a, b ->
      cond do
        is_nil(a.status) != is_nil(b.status) -> not is_nil(a.status)
        true -> DateTime.compare(a.updated_at, b.updated_at) == :gt
      end
    end)
  end

  defp apply_event({:manager, _module, :opened, entry}, sessions) do
    upsert(sessions, entry.id, fn existing ->
      %{
        id: entry.id,
        title: entry.title,
        status: entry.status,
        pid: entry.pid,
        updated_at: (existing && existing.updated_at) || DateTime.utc_now(),
        persisted?: (existing && existing.persisted?) || false
      }
    end)
    |> sort()
  end

  defp apply_event({:manager, _module, :status, %{id: id, status: status}}, sessions) do
    update_in_list(sessions, id, fn s -> %{s | status: status} end)
    |> sort()
  end

  defp apply_event({:manager, _module, :title, %{id: id, title: title}}, sessions) do
    update_in_list(sessions, id, fn s -> %{s | title: title} end)
  end

  defp apply_event({:manager, _module, :closed, %{id: id}}, sessions) do
    Enum.flat_map(sessions, fn
      %{id: ^id, persisted?: true} = s -> [%{s | status: nil, pid: nil}]
      %{id: ^id} -> []
      s -> [s]
    end)
    |> sort()
  end

  defp apply_event(_other, sessions), do: sessions

  defp upsert(sessions, id, fun) do
    case Enum.find_index(sessions, &(&1.id == id)) do
      nil -> [fun.(nil) | sessions]
      idx -> List.update_at(sessions, idx, fn s -> fun.(s) end)
    end
  end

  defp update_in_list(sessions, id, fun) do
    Enum.map(sessions, fn
      %{id: ^id} = s -> fun.(s)
      s -> s
    end)
  end
end
