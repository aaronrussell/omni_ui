defmodule OmniUI.TitleServiceTest do
  use OmniUI.SessionCase, async: true

  alias OmniUI.TitleService

  @moduletag :tmp_dir

  defp start_service!(opts) do
    name = opts[:name] || unique_name("TS")
    start_supervised!({TitleService, Keyword.put(opts, :name, name)})
    name
  end

  # Spawn a session under `manager`, with the agent's HTTP stubbed to a
  # single text response. Returns the session pid + id. The session
  # process is granted access to the stub via `Req.Test.allow/3` —
  # `$callers` doesn't propagate through `DynamicSupervisor.start_child`,
  # so without the explicit allow the agent's HTTP request can't find
  # the stub owner.
  defp start_untitled_session!(manager, opts \\ []) do
    stub_name = unique_stub_name()
    stub_fixture(stub_name, opts[:fixture] || @text_fixture)

    pid =
      create_session!(manager,
        agent: [model: model(), opts: stub_opts(stub_name)],
        subscribe: false,
        title: opts[:title]
      )

    Req.Test.allow(stub_name, self(), pid)

    id = Omni.Session.get_snapshot(pid).id
    {pid, id}
  end

  defp service_state(name), do: :sys.get_state(Process.whereis(name))

  describe "init" do
    test "starts with an empty pending map when no sessions are running", ctx do
      manager = start_manager!(ctx)
      service = start_service!(manager: manager, model: nil)

      assert service_state(service).pending == %{}
    end

    test "tracks running, untitled sessions discovered on boot", ctx do
      manager = start_manager!(ctx)
      {pid, id} = start_untitled_session!(manager)

      service = start_service!(manager: manager, model: nil)

      state = service_state(service)
      assert Map.has_key?(state.pending, id)
      assert state.pending[id].pid == pid
      assert state.pending[id].task == nil
    end

    test "ignores running sessions that already have a title", ctx do
      manager = start_manager!(ctx)
      {_pid, id} = start_untitled_session!(manager, title: "Pre-set")

      service = start_service!(manager: manager, model: nil)

      refute Map.has_key?(service_state(service).pending, id)
    end

    test "applies start opts over app env", ctx do
      Application.put_env(:omni_ui, TitleService, manager: :wrong_manager, model: nil)
      on_exit(fn -> Application.delete_env(:omni_ui, TitleService) end)

      manager = start_manager!(ctx)
      service = start_service!(manager: manager, model: nil)

      assert service_state(service).manager == manager
    end
  end

  describe ":opened events" do
    test "tracks a newly opened untitled session", ctx do
      manager = start_manager!(ctx)
      service = start_service!(manager: manager, model: nil)

      {pid, id} = start_untitled_session!(manager)

      assert eventually(fn -> Map.has_key?(service_state(service).pending, id) end)
      assert service_state(service).pending[id].pid == pid
    end

    test "ignores newly opened sessions that already carry a title", ctx do
      manager = start_manager!(ctx)
      service = start_service!(manager: manager, model: nil)

      {_pid, id} = start_untitled_session!(manager, title: "Already named")

      # No async signal to wait on; give the service room to process the
      # :opened event before asserting absence.
      refute eventually(fn -> Map.has_key?(service_state(service).pending, id) end, 200)
    end

    test "is idempotent if a duplicate :opened arrives for an already-tracked session", ctx do
      manager = start_manager!(ctx)
      service = start_service!(manager: manager, model: nil)

      {pid, id} = start_untitled_session!(manager)
      assert eventually(fn -> Map.has_key?(service_state(service).pending, id) end)

      original_monitor = service_state(service).pending[id].monitor

      send(service, {:manager, manager, :opened, %{id: id, title: nil, pid: pid, status: :idle}})
      Process.sleep(20)

      assert service_state(service).pending[id].monitor == original_monitor
    end
  end

  describe "turn -> generate -> set_title flow" do
    test "auto-generates and sets a title on :turn {:stop, _} (heuristic)", ctx do
      manager = start_manager!(ctx)
      service = start_service!(manager: manager, model: nil)

      {pid, id} = start_untitled_session!(manager)
      assert eventually(fn -> Map.has_key?(service_state(service).pending, id) end)

      :ok = Omni.Session.prompt(pid, "Hello world")

      assert eventually(fn -> Omni.Session.get_title(pid) == "Hello world" end, 3_000)
      # After setting, the service untracks (via the :title round-trip).
      assert eventually(fn -> not Map.has_key?(service_state(service).pending, id) end)
    end

    test "ignores duplicate :turn events while a generation task is in flight", ctx do
      manager = start_manager!(ctx)
      service = start_service!(manager: manager, model: nil)

      {pid, id} = start_untitled_session!(manager)
      assert eventually(fn -> Map.has_key?(service_state(service).pending, id) end)

      # Inject a sentinel task into the entry to simulate "generation in
      # flight", then send a synthetic :turn — the service should leave
      # the existing task alone.
      sentinel = Task.async(fn -> Process.sleep(:infinity) end)

      :sys.replace_state(service, fn state ->
        entry = %{state.pending[id] | task: sentinel}

        %{
          state
          | pending: Map.put(state.pending, id, entry),
            task_refs: Map.put(state.task_refs, sentinel.ref, id)
        }
      end)

      send(service, {:session, pid, :turn, {:stop, %{dummy: true}}})
      Process.sleep(20)

      assert service_state(service).pending[id].task == sentinel

      Task.shutdown(sentinel, :brutal_kill)
    end
  end

  describe ":title events" do
    test "untracks a session when a non-nil title is set externally", ctx do
      manager = start_manager!(ctx)
      service = start_service!(manager: manager, model: nil)

      {pid, id} = start_untitled_session!(manager)
      assert eventually(fn -> Map.has_key?(service_state(service).pending, id) end)

      :ok = Omni.Session.set_title(pid, "Manual title")

      assert eventually(fn -> not Map.has_key?(service_state(service).pending, id) end)
    end

    test "re-subscribes when a previously-titled session has its title cleared", ctx do
      manager = start_manager!(ctx)
      service = start_service!(manager: manager, model: nil)

      {pid, id} = start_untitled_session!(manager, title: "Initial")
      # Service should NOT track an already-titled session.
      refute eventually(fn -> Map.has_key?(service_state(service).pending, id) end, 100)

      :ok = Omni.Session.set_title(pid, nil)

      assert eventually(fn -> Map.has_key?(service_state(service).pending, id) end)
      assert service_state(service).pending[id].pid == pid
    end
  end

  describe ":closed events" do
    test "drops a tracked entry when its session closes", ctx do
      manager = start_manager!(ctx)
      service = start_service!(manager: manager, model: nil)

      {_pid, id} = start_untitled_session!(manager)
      assert eventually(fn -> Map.has_key?(service_state(service).pending, id) end)

      :ok = Omni.Session.Manager.close(manager, id)

      assert eventually(fn -> not Map.has_key?(service_state(service).pending, id) end)
    end
  end

  describe "session DOWN" do
    @tag :capture_log
    test "drops a tracked entry when its session terminates abnormally", ctx do
      manager = start_manager!(ctx)
      service = start_service!(manager: manager, model: nil)

      {pid, id} = start_untitled_session!(manager)
      assert eventually(fn -> Map.has_key?(service_state(service).pending, id) end)

      Process.exit(pid, :kill)

      assert eventually(fn -> not Map.has_key?(service_state(service).pending, id) end)
    end
  end
end
