defmodule Omni.UI.AgentLiveTest do
  use Omni.UI.LiveCase, async: false

  describe "mount" do
    test "does NOT create a session (lazy creation)", %{conn: conn} do
      {:ok, _view, _html} = live(conn, "/")
      Process.sleep(50)

      open_ids = Sessions.list_open() |> Enum.map(& &1.id) |> MapSet.new()

      assert MapSet.size(open_ids) == 0,
             "expected mount on / to create zero sessions; got: " <>
               inspect(MapSet.to_list(open_ids))
    end

    test "renders the chat interface, editor, and both side panels", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "Sessions"
      assert html =~ ~s(title="New session")
      assert html =~ "Untitled"
      assert html =~ ~s(title="Sessions")
      assert html =~ ~s(title="Open files panel")
    end

    test "with ?session_id attaches and renders the session title", %{conn: conn} do
      {_pid, id} = seed_session!(title: "My Test Chat")

      {:ok, _view, html} = live(conn, "/?session_id=#{id}")

      assert html =~ "My Test Chat"
    end

    test "with invalid ?session_id patches to / and shows warning", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?session_id=does-not-exist")

      html = render(view)
      assert html =~ "Untitled"
      assert html =~ "Session not found"
    end
  end

  describe "toggle event" do
    test "toggles sessions panel open/closed", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")

      assert html =~ ~s(title="Sessions")
      toggled = view |> element(~s(button[title="Sessions"])) |> render_click()
      refute toggled =~ "translate-x-0"

      reopened = view |> element(~s(button[title="Sessions"])) |> render_click()
      assert reopened =~ "translate-x-0"
    end

    test "toggles files panel open/closed", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      opened = view |> element(~s(button[title="Open files panel"])) |> render_click()
      assert opened =~ "translate-x-0"
    end
  end

  describe "session navigation" do
    test "open_session push_patches to /?session_id=<id>", %{conn: conn} do
      {_pid, id} = seed_session!(title: "Target Session")

      {:ok, view, _html} = live(conn, "/")

      render_click(view, "open_session", %{"session-id" => id})

      assert_patch(view, "/?session_id=#{id}")
    end

    test "new_session push_patches to /", %{conn: conn} do
      {_pid, id} = seed_session!(title: "Current Session")

      {:ok, view, _html} = live(conn, "/?session_id=#{id}")

      render_click(view, "new_session", %{})

      assert_patch(view, "/")
    end
  end

  describe "open_file event" do
    test "opens the files panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      render_click(view, "open_file", %{"filename" => "hello.html"})
      html = render(view)

      assert html =~ "All files"
    end
  end

  describe "manager events" do
    test "session created externally surfaces in the sessions panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      external_id = "ext-#{System.unique_integer([:positive])}"

      spawn(fn ->
        {:ok, _pid} =
          Sessions.create(
            id: external_id,
            title: "External Session",
            agent: agent_opts()
          )

        Process.sleep(2_000)
      end)

      wait_until(fn ->
        if render(view) =~ "External Session", do: :done
      end)

      assert render(view) =~ "External Session"
    end
  end

  describe "active_session_deleted" do
    test "redirects to / when the active session is deleted", %{conn: conn} do
      {_pid, id} = seed_session!(title: "Doomed Session")

      {:ok, view, _html} = live(conn, "/?session_id=#{id}")

      send(view.pid, :active_session_deleted)

      assert_patch(view, "/")
    end
  end

  describe "model configuration" do
    setup do
      original = Application.get_env(:omni_ui, Omni.UI.AgentLive, [])
      on_exit(fn -> Application.put_env(:omni_ui, Omni.UI.AgentLive, original) end)
      :ok
    end

    test "unknown provider is silently skipped", %{conn: conn} do
      Application.put_env(:omni_ui, Omni.UI.AgentLive,
        providers: [:ollama, :nonexistent_provider],
        default_model: {:ollama, "gemma4:latest"}
      )

      {:ok, _view, _html} = live(conn, "/")
    end

    test "empty providers hides model select (fixed model pattern)", %{conn: conn} do
      Application.put_env(:omni_ui, Omni.UI.AgentLive, default_model: {:ollama, "gemma4:latest"})

      {:ok, _view, html} = live(conn, "/")

      refute html =~ "model-select"
    end

    test "falls back to first model when no default configured", %{conn: conn} do
      Application.put_env(:omni_ui, Omni.UI.AgentLive, providers: [:ollama])

      {:ok, _view, html} = live(conn, "/")

      assert html =~ "model-select"
    end

    test "falls back to first model when default not in provider models", %{conn: conn} do
      import ExUnit.CaptureLog

      Application.put_env(:omni_ui, Omni.UI.AgentLive,
        providers: [:ollama],
        default_model: {:ollama, "nonexistent-model"}
      )

      log =
        capture_log(fn ->
          {:ok, _view, _html} = live(conn, "/")
        end)

      assert log =~ "not found in provider models"
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp seed_session!(opts) do
    title = Keyword.get(opts, :title)
    id = "test-#{System.unique_integer([:positive])}"

    caller = self()

    _pid =
      spawn(fn ->
        {:ok, session_pid} =
          Sessions.create(
            id: id,
            title: title,
            agent: agent_opts(),
            subscribe: false
          )

        send(caller, {:session_ready, session_pid})
        Process.sleep(10_000)
      end)

    receive do
      {:session_ready, session_pid} -> {session_pid, id}
    after
      5_000 -> raise "seed_session! timed out waiting for session #{id}"
    end
  end

  defp agent_opts do
    {:ok, model} = Omni.get_model(:anthropic, "claude-haiku-4-5")
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
end
