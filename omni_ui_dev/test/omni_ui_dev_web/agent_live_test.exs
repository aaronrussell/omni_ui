defmodule OmniUIDevWeb.AgentLiveTest do
  use OmniUIDevWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias OmniUI.Sessions

  setup do
    # Snapshot every session id present at test start — both persisted (in
    # the store) and currently running. Cleanup only touches ids NOT in this
    # baseline, so we never wipe sessions that pre-existed the test.
    baseline_open = Sessions.list_open() |> Enum.map(& &1.id) |> MapSet.new()
    {:ok, persisted} = Sessions.list()
    baseline_persisted = persisted |> Enum.map(& &1.id) |> MapSet.new()
    baseline = MapSet.union(baseline_open, baseline_persisted)

    on_exit(fn -> cleanup_sessions(baseline) end)

    {:ok, baseline_open: baseline_open}
  end

  describe "OmniUI.AgentLive mounted under OmniUI.Sessions Manager" do
    test "mount on / does NOT create a session (lazy creation)", %{
      conn: conn,
      baseline_open: baseline
    } do
      {:ok, _view, _html} = live(conn, "/")

      # Give any background work a tick to land before asserting absence.
      Process.sleep(50)

      assert MapSet.size(added_session_ids(baseline)) == 0,
             "expected mount on / to create zero sessions; got: " <>
               inspect(MapSet.to_list(added_session_ids(baseline)))
    end

    test "renders the SessionsComponent's panel header", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ ~r/Sessions/
      assert html =~ ~r/title=\"New session\"/
    end

    test "a Manager.create from another process surfaces in the LV's panel", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/")

      external_id = "ext-" <> Integer.to_string(System.unique_integer([:positive]))

      # Spawn (not Task.async) so the controller stays alive past this test.
      # The spawned process is the only :controller; on_exit cleanup tears
      # everything down via Sessions.delete/1.
      _spawned =
        spawn(fn ->
          {:ok, _pid} =
            Sessions.create(
              id: external_id,
              title: "External Session",
              agent: agent_opts()
            )

          # Stay alive long enough for the LV to render and the test to assert.
          Process.sleep(2_000)
        end)

      wait_until(fn ->
        if render(view) =~ "External Session", do: :done
      end)

      assert render(view) =~ "External Session"
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp added_session_ids(baseline) do
    Sessions.list_open()
    |> Enum.map(& &1.id)
    |> MapSet.new()
    |> MapSet.difference(baseline)
  end

  defp agent_opts do
    {:ok, model} = Omni.get_model(:ollama, "gemma4:latest")
    [model: model]
  end

  defp wait_until(fun, timeout \\ 1500) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait(fun, deadline)
  end

  defp do_wait(fun, deadline) do
    case fun.() do
      :done ->
        :done

      _ ->
        if System.monotonic_time(:millisecond) > deadline do
          flunk("wait_until timed out")
        else
          Process.sleep(20)
          do_wait(fun, deadline)
        end
    end
  end

  # Drop any sessions this test set created from the store, so we don't
  # accumulate cruft in priv/sessions/.
  defp cleanup_sessions(baseline) do
    {:ok, all} = Sessions.list()

    all
    |> Enum.reject(fn %{id: id} -> MapSet.member?(baseline, id) end)
    |> Enum.each(fn %{id: id} -> Sessions.delete(id) end)

    Enum.each(Sessions.list_open(), fn %{id: id} ->
      unless MapSet.member?(baseline, id), do: Sessions.delete(id)
    end)
  end
end
