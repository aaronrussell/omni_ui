defmodule OmniUI.SessionLifecycleTest do
  use OmniUI.SessionCase, async: true

  alias Phoenix.LiveView.Socket

  # `attach_session/2` calls `manager.open/2`, so the manager argument
  # must be a module that `use`s `Omni.Session.Manager` (not the
  # registered-name atom that `start_manager!/1` returns by default).
  # This dedicated test module mirrors how production wires
  # `OmniUI.Sessions` while keeping the test isolated.
  defmodule TestManager do
    use Omni.Session.Manager, otp_app: :omni_ui
  end

  @moduletag :tmp_dir

  setup ctx do
    start_supervised!({TestManager, store: tmp_store(ctx)})
    :ok
  end

  defp build_socket do
    %Socket{
      assigns: %{__changed__: %{}},
      private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}}
    }
  end

  defp seed_session!(opts \\ []) do
    stub_name = unique_stub_name()
    stub_fixture(stub_name, @text_fixture)

    {:ok, pid} =
      TestManager.create(
        agent: [model: model(), opts: stub_opts(stub_name)],
        subscribe: false,
        title: opts[:title]
      )

    Req.Test.allow(stub_name, self(), pid)
    id = Omni.Session.get_snapshot(pid).id

    {pid, id}
  end

  defp init_socket do
    OmniUI.init_session(build_socket(), manager: TestManager, model: model())
  end

  describe "attach_session/2" do
    test "attaches an existing session and applies its snapshot to the socket" do
      {pid, id} = seed_session!(title: "Pre-titled")

      socket = OmniUI.attach_session(init_socket(), id: id)

      assert socket.assigns.session == pid
      assert Process.alive?(socket.assigns.session)
      assert socket.assigns.session_id == id
      assert socket.assigns.title == "Pre-titled"
      assert %Omni.Session.Tree{} = socket.assigns.tree
      assert socket.assigns.url_synced == true
      assert socket.assigns.current_turn == nil
    end

    test "raises when the id is not found in the store" do
      assert_raise RuntimeError, ~r/Omni.Session .* not found/, fn ->
        OmniUI.attach_session(init_socket(), id: "does-not-exist")
      end
    end

    test "id: nil resets the socket to a blank session state" do
      {_pid, id} = seed_session!(title: "Pre-titled")

      socket =
        init_socket()
        |> OmniUI.attach_session(id: id)
        |> OmniUI.attach_session(id: nil)

      assert socket.assigns.session == nil
      assert socket.assigns.session_id == nil
      assert socket.assigns.title == nil
      assert socket.assigns.tree == nil
      assert socket.assigns.current_turn == nil
      assert socket.assigns.url_synced == false
    end

    test "is a no-op when the same id is reattached" do
      {_pid, id} = seed_session!()

      attached = OmniUI.attach_session(init_socket(), id: id)
      reattached = OmniUI.attach_session(attached, id: id)

      assert reattached.assigns.session == attached.assigns.session
      assert reattached.assigns.session_id == attached.assigns.session_id
    end
  end
end
