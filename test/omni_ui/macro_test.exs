defmodule OmniUI.MacroTest do
  use ExUnit.Case, async: true

  alias OmniUI.Test.{MinimalView, CustomHandlersView, CustomAgentEventView}

  setup_all do
    Code.ensure_loaded!(OmniUI)
    Code.ensure_loaded!(MinimalView)
    Code.ensure_loaded!(CustomHandlersView)
    Code.ensure_loaded!(CustomAgentEventView)
    :ok
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
    test "start_agent/2 is exported" do
      assert function_exported?(OmniUI, :start_agent, 2)
    end

    test "update_agent/2 is exported" do
      assert function_exported?(OmniUI, :update_agent, 2)
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
