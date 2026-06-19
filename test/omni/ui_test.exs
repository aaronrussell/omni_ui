defmodule Omni.UITest do
  use ExUnit.Case

  describe "tool_timeout/1" do
    setup do
      prev = Application.get_env(:omni_ui, Omni.UI)
      on_exit(fn -> Application.put_env(:omni_ui, Omni.UI, prev || []) end)
      Application.delete_env(:omni_ui, Omni.UI)
      :ok
    end

    test "returns built-in defaults for known tools" do
      assert Omni.UI.tool_timeout("repl") == 65_000
      assert Omni.UI.tool_timeout("bash") == 35_000
      assert Omni.UI.tool_timeout("web_fetch") == 20_000
    end

    test "returns default fallback for unknown tools" do
      assert Omni.UI.tool_timeout("files") == 10_000
      assert Omni.UI.tool_timeout("custom_tool") == 10_000
    end

    test "app config tool_timeouts map overrides built-in defaults" do
      Application.put_env(:omni_ui, Omni.UI, tool_timeouts: %{"repl" => 120_000})

      assert Omni.UI.tool_timeout("repl") == 120_000
      assert Omni.UI.tool_timeout("bash") == 35_000
    end

    test "app config default_tool_timeout overrides the fallback" do
      Application.put_env(:omni_ui, Omni.UI, default_tool_timeout: 15_000)

      assert Omni.UI.tool_timeout("files") == 15_000
      assert Omni.UI.tool_timeout("repl") == 65_000
    end
  end
end
