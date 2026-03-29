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
end
