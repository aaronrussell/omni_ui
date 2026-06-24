defmodule Omni.UI.SessionsComponentTest.MockManager do
  @moduledoc false
  use Agent

  def start_link(opts \\ []) do
    persisted = Keyword.get(opts, :persisted, [])
    open = Keyword.get(opts, :open, [])
    Agent.start_link(fn -> %{persisted: persisted, open: open, calls: []} end, name: __MODULE__)
  end

  def list do
    {:ok, Agent.get(__MODULE__, & &1.persisted)}
  end

  def list_open do
    Agent.get(__MODULE__, & &1.open)
  end

  def rename(id, title) do
    Agent.update(__MODULE__, fn state ->
      %{state | calls: [{:rename, id, title} | state.calls]}
    end)

    :ok
  end

  def delete(id) do
    Agent.update(__MODULE__, fn state ->
      %{state | calls: [{:delete, id} | state.calls]}
    end)

    :ok
  end

  def calls do
    Agent.get(__MODULE__, & &1.calls) |> Enum.reverse()
  end
end

defmodule Omni.UI.SessionsComponentTest do
  use ExUnit.Case, async: false

  alias Phoenix.LiveView.Socket
  alias Omni.UI.SessionsComponent
  alias Omni.UI.SessionsComponentTest.MockManager

  defp build_socket(assigns \\ %{}) do
    %Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns),
      private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}}
    }
  end

  defp mount_component do
    {:ok, socket} = SessionsComponent.mount(build_socket())
    socket
  end

  defp apply_update(socket, assigns) do
    {:ok, socket} = SessionsComponent.update(assigns, socket)
    socket
  end

  defp persisted_session(id, opts \\ []) do
    %{
      id: id,
      title: Keyword.get(opts, :title),
      updated_at: Keyword.get(opts, :updated_at, DateTime.utc_now())
    }
  end

  defp open_session(id, opts) do
    %{
      id: id,
      title: Keyword.get(opts, :title),
      status: Keyword.get(opts, :status, :idle),
      pid: Keyword.get(opts, :pid, self())
    }
  end

  defp start_mock!(opts) do
    start_supervised!({MockManager, opts})
  end

  # ── mount ───────────────────────────────────────────────────────

  describe "mount/1" do
    test "initialises sessions to nil" do
      socket = mount_component()
      assert socket.assigns.sessions == nil
    end
  end

  # ── update: initial load ────────────────────────────────────────

  describe "update/2 initial load" do
    test "loads and merges persisted and open sessions" do
      now = DateTime.utc_now()

      start_mock!(
        persisted: [persisted_session("s1", title: "Saved", updated_at: now)],
        open: [open_session("s2", title: "Running", status: :busy)]
      )

      socket =
        mount_component()
        |> apply_update(%{id: "sessions", current_id: nil, manager: MockManager})

      ids = Enum.map(socket.assigns.sessions, & &1.id)
      assert "s1" in ids
      assert "s2" in ids
    end

    test "sorts sessions by updated_at descending" do
      old = DateTime.add(DateTime.utc_now(), -3600, :second)
      recent = DateTime.utc_now()

      start_mock!(
        persisted: [
          persisted_session("old", updated_at: old),
          persisted_session("recent", updated_at: recent)
        ]
      )

      socket =
        mount_component()
        |> apply_update(%{id: "sessions", current_id: nil, manager: MockManager})

      ids = Enum.map(socket.assigns.sessions, & &1.id)
      assert ids == ["recent", "old"]
    end

    test "merges data when session is both persisted and open" do
      now = DateTime.utc_now()

      start_mock!(
        persisted: [persisted_session("s1", title: "Stored title", updated_at: now)],
        open: [open_session("s1", title: "Live title", status: :busy)]
      )

      socket =
        mount_component()
        |> apply_update(%{id: "sessions", current_id: nil, manager: MockManager})

      session = Enum.find(socket.assigns.sessions, &(&1.id == "s1"))
      assert session.title == "Live title"
      assert session.status == :busy
      assert session.persisted? == true
    end

    test "does not reload sessions on subsequent updates" do
      start_mock!(persisted: [persisted_session("s1")])

      socket =
        mount_component()
        |> apply_update(%{id: "sessions", current_id: nil, manager: MockManager})

      assert length(socket.assigns.sessions) == 1

      socket = apply_update(socket, %{id: "sessions", current_id: "s1", manager: MockManager})

      assert length(socket.assigns.sessions) == 1
    end
  end

  # ── update: manager_event ───────────────────────────────────────

  describe "update/2 with manager_event" do
    setup do
      start_mock!(persisted: [persisted_session("s1", title: "First")])

      socket =
        mount_component()
        |> apply_update(%{id: "sessions", current_id: nil, manager: MockManager})

      %{socket: socket}
    end

    test ":opened adds a new session", %{socket: socket} do
      entry = %{id: "s2", title: "New", status: :idle, pid: self()}
      event = {:manager, MockManager, :opened, entry}

      socket = apply_update(socket, %{manager_event: event})

      ids = Enum.map(socket.assigns.sessions, & &1.id)
      assert "s2" in ids
    end

    test ":opened updates an existing session", %{socket: socket} do
      entry = %{id: "s1", title: "Updated", status: :busy, pid: self()}
      event = {:manager, MockManager, :opened, entry}

      socket = apply_update(socket, %{manager_event: event})

      session = Enum.find(socket.assigns.sessions, &(&1.id == "s1"))
      assert session.title == "Updated"
      assert session.status == :busy
    end

    test ":status updates session status", %{socket: socket} do
      event = {:manager, MockManager, :status, %{id: "s1", status: :paused}}

      socket = apply_update(socket, %{manager_event: event})

      session = Enum.find(socket.assigns.sessions, &(&1.id == "s1"))
      assert session.status == :paused
    end

    test ":title updates session title", %{socket: socket} do
      event = {:manager, MockManager, :title, %{id: "s1", title: "Renamed"}}

      socket = apply_update(socket, %{manager_event: event})

      session = Enum.find(socket.assigns.sessions, &(&1.id == "s1"))
      assert session.title == "Renamed"
    end

    test ":closed removes non-persisted session", %{socket: socket} do
      entry = %{id: "temp", title: nil, status: :idle, pid: self()}
      event_open = {:manager, MockManager, :opened, entry}
      socket = apply_update(socket, %{manager_event: event_open})

      ids_before = Enum.map(socket.assigns.sessions, & &1.id)
      assert "temp" in ids_before

      event_close = {:manager, MockManager, :closed, %{id: "temp"}}
      socket = apply_update(socket, %{manager_event: event_close})

      ids_after = Enum.map(socket.assigns.sessions, & &1.id)
      refute "temp" in ids_after
    end

    test ":closed nils out status on persisted session", %{socket: socket} do
      entry = %{id: "s1", title: "First", status: :busy, pid: self()}
      event_open = {:manager, MockManager, :opened, entry}
      socket = apply_update(socket, %{manager_event: event_open})

      event_close = {:manager, MockManager, :closed, %{id: "s1"}}
      socket = apply_update(socket, %{manager_event: event_close})

      session = Enum.find(socket.assigns.sessions, &(&1.id == "s1"))
      assert session != nil
      assert session.status == nil
      assert session.pid == nil
    end

    test "unknown event is a no-op", %{socket: socket} do
      event = {:manager, MockManager, :unknown_event, %{}}
      socket_after = apply_update(socket, %{manager_event: event})

      assert socket_after.assigns.sessions == socket.assigns.sessions
    end
  end

  # ── handle_event: rename ────────────────────────────────────────

  describe "handle_event rename" do
    setup do
      start_mock!(persisted: [persisted_session("s1", title: "Original")])

      socket =
        mount_component()
        |> apply_update(%{id: "sessions", current_id: nil, manager: MockManager})

      %{socket: socket}
    end

    test "calls manager.rename with trimmed title", %{socket: socket} do
      {:noreply, _socket} =
        SessionsComponent.handle_event(
          "rename",
          %{"session_id" => "s1", "title" => "  New Name  "},
          socket
        )

      assert {:rename, "s1", "New Name"} in MockManager.calls()
    end

    test "passes nil for blank title", %{socket: socket} do
      {:noreply, _socket} =
        SessionsComponent.handle_event(
          "rename",
          %{"session_id" => "s1", "title" => "   "},
          socket
        )

      assert {:rename, "s1", nil} in MockManager.calls()
    end
  end

  # ── handle_event: delete ────────────────────────────────────────

  describe "handle_event delete" do
    setup do
      start_mock!(
        persisted: [
          persisted_session("s1", title: "Keep"),
          persisted_session("s2", title: "Delete")
        ]
      )

      socket =
        mount_component()
        |> apply_update(%{id: "sessions", current_id: "s1", manager: MockManager})

      %{socket: socket}
    end

    test "removes the session from the list", %{socket: socket} do
      {:noreply, socket} =
        SessionsComponent.handle_event("delete", %{"id" => "s2"}, socket)

      ids = Enum.map(socket.assigns.sessions, & &1.id)
      assert "s1" in ids
      refute "s2" in ids
    end

    test "calls manager.delete", %{socket: socket} do
      {:noreply, _socket} =
        SessionsComponent.handle_event("delete", %{"id" => "s2"}, socket)

      assert {:delete, "s2"} in MockManager.calls()
    end

    test "sends :active_session_deleted when deleting current session", %{socket: socket} do
      {:noreply, _socket} =
        SessionsComponent.handle_event("delete", %{"id" => "s1"}, socket)

      assert_received :active_session_deleted
    end

    test "does not send :active_session_deleted for non-current session", %{socket: socket} do
      {:noreply, _socket} =
        SessionsComponent.handle_event("delete", %{"id" => "s2"}, socket)

      refute_received :active_session_deleted
    end
  end
end
