defmodule OmniUI.MacroTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket

  alias OmniUI.Test.{
    BadAgentEventView,
    CustomAgentEventView,
    CustomHandlersView,
    MinimalView
  }

  setup_all do
    Code.ensure_loaded!(OmniUI)
    Code.ensure_loaded!(MinimalView)
    Code.ensure_loaded!(CustomHandlersView)
    Code.ensure_loaded!(CustomAgentEventView)
    Code.ensure_loaded!(BadAgentEventView)
    :ok
  end

  defp build_socket(assigns \\ %{}) do
    %Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns),
      private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}}
    }
  end

  describe "behaviour" do
    test "defines agent_event/3 callback" do
      callbacks = OmniUI.behaviour_info(:callbacks)
      assert {:agent_event, 3} in callbacks
    end
  end

  describe "macro injection — MinimalView (no developer handlers)" do
    test "injects handle_event/3" do
      assert function_exported?(MinimalView, :handle_event, 3)
    end

    test "injects handle_info/2" do
      assert function_exported?(MinimalView, :handle_info, 2)
    end

    test "injects default agent_event/3" do
      assert function_exported?(MinimalView, :agent_event, 3)
    end
  end

  describe "macro injection — CustomHandlersView (developer defines handlers)" do
    test "exports handle_event/3" do
      assert function_exported?(CustomHandlersView, :handle_event, 3)
    end

    test "exports handle_info/2" do
      assert function_exported?(CustomHandlersView, :handle_info, 2)
    end

    test "injects default agent_event/3" do
      assert function_exported?(CustomHandlersView, :agent_event, 3)
    end
  end

  describe "macro injection — CustomAgentEventView (developer defines agent_event)" do
    test "exports developer's agent_event/3" do
      assert function_exported?(CustomAgentEventView, :agent_event, 3)
    end
  end

  describe "public API" do
    test "init_session/2 is exported" do
      assert function_exported?(OmniUI, :init_session, 2)
    end

    test "attach_session/2 is exported" do
      assert function_exported?(OmniUI, :attach_session, 2)
    end

    test "ensure_session/1 is exported" do
      assert function_exported?(OmniUI, :ensure_session, 1)
    end

    test "update_session/2 is exported" do
      assert function_exported?(OmniUI, :update_session, 2)
    end

    test "notify/2 and notify/3 are exported" do
      assert function_exported?(OmniUI, :notify, 2)
      assert function_exported?(OmniUI, :notify, 3)
    end
  end

  describe "init_session/2" do
    test "populates every OmniUI-owned assign" do
      socket = OmniUI.init_session(build_socket(), model: {:anthropic, "claude-haiku-4-5"})

      for key <- [
            :manager,
            :agent_module,
            :model,
            :thinking,
            :system,
            :tools,
            :tool_timeout,
            :tool_components,
            :session,
            :session_id,
            :title,
            :tree,
            :current_turn,
            :usage,
            :notification_ids,
            :url_synced
          ] do
        assert Map.has_key?(socket.assigns, key), "missing assign: #{inspect(key)}"
      end
    end

    test "leaves session-state assigns blank — session is attached later" do
      socket = OmniUI.init_session(build_socket(), model: {:anthropic, "claude-haiku-4-5"})

      assert socket.assigns.session == nil
      assert socket.assigns.session_id == nil
      assert socket.assigns.title == nil
      assert socket.assigns.tree == nil
      assert socket.assigns.current_turn == nil
      assert socket.assigns.usage == %Omni.Usage{}
      assert socket.assigns.notification_ids == []
      assert socket.assigns.url_synced == false
    end

    test "initialises :turns and :notifications streams" do
      socket = OmniUI.init_session(build_socket(), model: {:anthropic, "claude-haiku-4-5"})

      assert Map.has_key?(socket.assigns, :streams)
      assert Map.has_key?(socket.assigns.streams, :turns)
      assert Map.has_key?(socket.assigns.streams, :notifications)
    end

    test ":manager defaults to OmniUI.Sessions" do
      socket = OmniUI.init_session(build_socket(), model: {:anthropic, "claude-haiku-4-5"})

      assert socket.assigns.manager == OmniUI.Sessions
    end

    test ":manager honours an explicit override" do
      socket =
        OmniUI.init_session(build_socket(),
          model: {:anthropic, "claude-haiku-4-5"},
          manager: SomeOtherManager
        )

      assert socket.assigns.manager == SomeOtherManager
    end

    test "resolves a {provider, model_id} tuple to %Omni.Model{}" do
      socket = OmniUI.init_session(build_socket(), model: {:anthropic, "claude-haiku-4-5"})

      assert %Omni.Model{} = socket.assigns.model
    end

    test "raises ArgumentError on an unresolvable model ref" do
      assert_raise ArgumentError, ~r/failed to resolve model/, fn ->
        OmniUI.init_session(build_socket(), model: {:nope, "nothing"})
      end
    end

    test "normalises :tools entries into flat tools list and components map" do
      tool_a = Omni.Tool.new(name: "a", description: "test")
      tool_b = Omni.Tool.new(name: "b", description: "test")
      renderer = fn assigns -> assigns end

      socket =
        OmniUI.init_session(build_socket(),
          model: {:anthropic, "claude-haiku-4-5"},
          tools: [{tool_a, component: renderer}, tool_b]
        )

      assert socket.assigns.tools == [tool_a, tool_b]
      assert socket.assigns.tool_components == %{"a" => renderer}
    end

    test "explicit :tool_components wins over tuple-extracted components on key conflict" do
      tool_a = Omni.Tool.new(name: "a", description: "test")
      tuple_renderer = fn assigns -> assigns end
      explicit_renderer = fn assigns -> assigns end

      socket =
        OmniUI.init_session(build_socket(),
          model: {:anthropic, "claude-haiku-4-5"},
          tools: [{tool_a, component: tuple_renderer}],
          tool_components: %{"a" => explicit_renderer}
        )

      assert socket.assigns.tool_components == %{"a" => explicit_renderer}
    end
  end

  describe "update_session/2 (no session attached)" do
    defp init_socket do
      OmniUI.init_session(build_socket(), model: {:anthropic, "claude-haiku-4-5"})
    end

    test "updates :model when ref resolves" do
      socket = OmniUI.update_session(init_socket(), model: {:anthropic, "claude-sonnet-4-5"})

      assert %Omni.Model{id: "claude-sonnet-4-5"} = socket.assigns.model
    end

    @tag :capture_log
    test "ignores an unresolvable model ref and warns the user" do
      socket = init_socket()
      original_model = socket.assigns.model

      socket = OmniUI.update_session(socket, model: {:nope, "nothing"})

      assert socket.assigns.model == original_model
      assert_received {OmniUI, :notify, %OmniUI.Notification{level: :warning}}
    end

    test "updates :thinking" do
      socket = OmniUI.update_session(init_socket(), thinking: :high)

      assert socket.assigns.thinking == :high
    end

    test "updates :system" do
      socket = OmniUI.update_session(init_socket(), system: "be helpful")

      assert socket.assigns.system == "be helpful"
    end

    test "updates :tools and :tool_components together" do
      tool_a = Omni.Tool.new(name: "a", description: "test")
      renderer = fn assigns -> assigns end

      socket = OmniUI.update_session(init_socket(), tools: [{tool_a, component: renderer}])

      assert socket.assigns.tools == [tool_a]
      assert socket.assigns.tool_components == %{"a" => renderer}
    end
  end

  describe "macro-injected handle_info — session-event filter" do
    test "dispatches a session event when pid matches socket.assigns.session" do
      socket = build_socket(%{session: self(), current_turn: nil, tree: nil})

      assert {:noreply, %Socket{}} =
               MinimalView.handle_info({:session, self(), :status, :idle}, socket)
    end

    test "drops a session event from a different pid" do
      stale_pid = spawn(fn -> :ok end)
      socket = build_socket(%{session: self(), title: "untouched"})

      assert {:noreply, ^socket} =
               MinimalView.handle_info({:session, stale_pid, :title, "tampered"}, socket)
    end
  end

  describe "agent_event/3 return-value contract" do
    test "MinimalView round-trips a session event cleanly" do
      socket = build_socket(%{session: self(), current_turn: nil, tree: nil})

      assert {:noreply, %Socket{}} =
               MinimalView.handle_info({:session, self(), :status, :idle}, socket)
    end

    test "CustomAgentEventView round-trips a session event cleanly" do
      socket = build_socket(%{session: self(), current_turn: nil, tree: nil})

      assert {:noreply, %Socket{} = result} =
               CustomAgentEventView.handle_info({:session, self(), :status, :idle}, socket)

      assert result.assigns.last_agent_event == {:status, :idle}
    end

    test "raises if the developer's agent_event/3 returns a non-socket" do
      socket = build_socket(%{session: self(), current_turn: nil, tree: nil})

      assert_raise RuntimeError, ~r/agent_event\/3 must return a socket/, fn ->
        BadAgentEventView.handle_info({:session, self(), :status, :idle}, socket)
      end
    end
  end

  describe "normalise_tools/1" do
    defp tool(name), do: Omni.Tool.new(name: name, description: "test")
    defp renderer, do: fn assigns -> assigns end

    test "returns empty list and empty map for empty input" do
      assert {[], %{}} = OmniUI.normalise_tools([])
    end

    test "passes bare structs through without adding to components map" do
      a = tool("a")
      b = tool("b")

      assert {[^a, ^b], %{}} = OmniUI.normalise_tools([a, b])
    end

    test "extracts component from tuple entries" do
      a = tool("a")
      fun = renderer()

      assert {[^a], %{"a" => ^fun}} = OmniUI.normalise_tools([{a, component: fun}])
    end

    test "handles a mixed list of bare structs and tuples" do
      a = tool("a")
      b = tool("b")
      c = tool("c")
      fun_a = renderer()
      fun_c = renderer()

      assert {[^a, ^b, ^c], components} =
               OmniUI.normalise_tools([{a, component: fun_a}, b, {c, component: fun_c}])

      assert components == %{"a" => fun_a, "c" => fun_c}
    end

    test "tuple with empty keyword list is treated as bare (no component)" do
      a = tool("a")

      assert {[^a], %{}} = OmniUI.normalise_tools([{a, []}])
    end

    test "tuple with component: nil is treated as no component" do
      a = tool("a")

      assert {[^a], %{}} = OmniUI.normalise_tools([{a, component: nil}])
    end

    test "preserves order of the flat tool list" do
      tools = for n <- 1..5, do: tool("tool_#{n}")

      assert {result, %{}} = OmniUI.normalise_tools(tools)
      assert result == tools
    end
  end

  describe "store decoupling" do
    test "macro does not inject store delegate functions" do
      refute function_exported?(MinimalView, :save_tree, 3)
      refute function_exported?(MinimalView, :save_metadata, 3)
      refute function_exported?(MinimalView, :load_session, 1)
      refute function_exported?(MinimalView, :list_sessions, 0)
      refute function_exported?(MinimalView, :delete_session, 1)
      refute function_exported?(MinimalView, :__omni_store__, 0)
    end
  end
end
