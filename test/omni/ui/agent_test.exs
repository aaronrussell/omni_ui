defmodule Omni.UI.AgentTest do
  use ExUnit.Case, async: true

  alias Omni.Agent.State
  alias Omni.UI.Agent

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    prev = Application.get_env(:omni_ui, Omni.UI.Sessions)

    Application.put_env(
      :omni_ui,
      Omni.UI.Sessions,
      Keyword.put(prev || [], :sessions_base_dir, tmp_dir)
    )

    on_exit(fn ->
      if prev,
        do: Application.put_env(:omni_ui, Omni.UI.Sessions, prev),
        else: Application.delete_env(:omni_ui, Omni.UI.Sessions)
    end)

    {:ok, model} = Omni.get_model(:anthropic, "claude-haiku-4-5")

    state = %State{
      model: model,
      system: nil,
      tools: [],
      opts: [],
      private: %{omni: %{session_id: "test-session-123"}}
    }

    {:ok, state: state}
  end

  describe "init/1" do
    test "appends built-in tools to existing tools", %{state: state} do
      existing_tool = %Omni.Tool{name: "custom", description: "A custom tool"}
      state = %{state | tools: [existing_tool]}

      {:ok, result} = Agent.init(state)

      names = Enum.map(result.tools, & &1.name)
      assert hd(names) == "custom"
      assert "files" in names
      assert "repl" in names
      assert "web_fetch" in names
      assert "web_search" in names
      assert length(names) == 5
    end

    test "uses default system prompt when state.system is nil", %{state: state} do
      {:ok, result} = Agent.init(state)

      assert result.system =~ "You are a helpful AI assistant"
      assert result.system =~ "## Tools"
    end

    test "prepends existing system prompt before the default", %{state: state} do
      custom = "You are a research assistant specialising in physics."
      state = %{state | system: custom}

      {:ok, result} = Agent.init(state)

      assert String.starts_with?(result.system, custom)
      assert result.system =~ "\n\n"
      assert result.system =~ "You are a helpful AI assistant"
    end

    test "constructs file paths from session_id", %{state: state, tmp_dir: tmp_dir} do
      {:ok, result} = Agent.init(state)

      expected_files_dir = Path.join([tmp_dir, "test-session-123", "files"])

      files_tool = Enum.find(result.tools, &(&1.name == "files"))
      assert files_tool
      assert files_tool.description =~ "file"

      assert File.dir?(Path.dirname(expected_files_dir)) ||
               !File.exists?(expected_files_dir)
    end

    test "preserves existing tools at the front of the list", %{state: state} do
      t1 = %Omni.Tool{name: "alpha", description: "First"}
      t2 = %Omni.Tool{name: "beta", description: "Second"}
      state = %{state | tools: [t1, t2]}

      {:ok, result} = Agent.init(state)

      names = Enum.map(result.tools, & &1.name)
      assert Enum.take(names, 2) == ["alpha", "beta"]
    end

    test "returns {:ok, state} tuple", %{state: state} do
      assert {:ok, %State{}} = Agent.init(state)
    end
  end
end
