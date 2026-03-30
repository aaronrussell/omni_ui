defmodule OmniUI.MacroTest do
  use ExUnit.Case, async: true

  alias OmniUI.Test.{MinimalView, CustomHandlersView, CustomAgentEventView, StoreView}

  setup_all do
    Code.ensure_loaded!(OmniUI)
    Code.ensure_loaded!(MinimalView)
    Code.ensure_loaded!(CustomHandlersView)
    Code.ensure_loaded!(CustomAgentEventView)
    Code.ensure_loaded!(StoreView)
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

  describe "store injection — MinimalView (no store configured)" do
    test "save_tree returns :ok" do
      assert MinimalView.save_tree("s1", %OmniUI.Tree{}) == :ok
      assert MinimalView.save_tree("s1", %OmniUI.Tree{}, []) == :ok
    end

    test "save_metadata returns :ok" do
      assert MinimalView.save_metadata("s1", []) == :ok
      assert MinimalView.save_metadata("s1", [], []) == :ok
    end

    test "load_session returns {:error, :no_store}" do
      assert MinimalView.load_session("s1") == {:error, :no_store}
      assert MinimalView.load_session("s1", []) == {:error, :no_store}
    end

    test "list_sessions returns {:ok, []}" do
      assert MinimalView.list_sessions() == {:ok, []}
      assert MinimalView.list_sessions([]) == {:ok, []}
    end

    test "delete_session returns :ok" do
      assert MinimalView.delete_session("s1") == :ok
      assert MinimalView.delete_session("s1", []) == :ok
    end
  end

  describe "store injection — StoreView (store configured)" do
    test "exports all store functions" do
      assert function_exported?(StoreView, :save_tree, 2)
      assert function_exported?(StoreView, :save_tree, 3)
      assert function_exported?(StoreView, :save_metadata, 2)
      assert function_exported?(StoreView, :save_metadata, 3)
      assert function_exported?(StoreView, :load_session, 1)
      assert function_exported?(StoreView, :load_session, 2)
      assert function_exported?(StoreView, :list_sessions, 0)
      assert function_exported?(StoreView, :list_sessions, 1)
      assert function_exported?(StoreView, :delete_session, 1)
      assert function_exported?(StoreView, :delete_session, 2)
    end

    @tag :tmp_dir
    test "save_tree + load_session round-trip", %{tmp_dir: tmp_dir} do
      tree =
        %OmniUI.Tree{}
        |> OmniUI.Tree.push(Omni.message(role: :user, content: "hello"))
        |> OmniUI.Tree.push(Omni.message(role: :assistant, content: "hi"))

      assert :ok = StoreView.save_tree("s1", tree, base_path: tmp_dir)
      assert {:ok, loaded_tree, []} = StoreView.load_session("s1", base_path: tmp_dir)
      assert loaded_tree == tree
    end

    @tag :tmp_dir
    test "list_sessions returns saved session", %{tmp_dir: tmp_dir} do
      tree = %OmniUI.Tree{}
      assert :ok = StoreView.save_tree("s1", tree, base_path: tmp_dir)

      assert {:ok, [%{id: "s1"}]} = StoreView.list_sessions(base_path: tmp_dir)
    end

    @tag :tmp_dir
    test "delete_session removes session", %{tmp_dir: tmp_dir} do
      tree = %OmniUI.Tree{}
      assert :ok = StoreView.save_tree("s1", tree, base_path: tmp_dir)
      assert :ok = StoreView.delete_session("s1", base_path: tmp_dir)

      assert {:error, :not_found} = StoreView.load_session("s1", base_path: tmp_dir)
    end
  end
end
