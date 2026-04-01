defmodule OmniUI.REPL.ToolTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 120_000

  alias OmniUI.REPL.Tool

  defp call(input, opts \\ []) do
    tool = Tool.new(opts)
    tool.handler.(input)
  end

  describe "success formatting" do
    test "expression result only" do
      assert call(%{title: "add", code: "1 + 2"}) == "=> 3"
    end

    test "IO output with result" do
      result = call(%{title: "hello", code: ~S|IO.puts("hello"); :ok|})
      assert result == "hello\n\n=> :ok"
    end

    test "result is pretty-inspected" do
      result = call(%{title: "list", code: "[1, 2, 3]"})
      assert result == "=> [1, 2, 3]"
    end

    test "nil result is shown" do
      assert call(%{title: "nil", code: "nil"}) == "=> nil"
    end

    test "title field is not included in output" do
      result = call(%{title: "this should not appear", code: ":ok"})
      refute result =~ "this should not appear"
      assert result == "=> :ok"
    end
  end

  describe "error formatting" do
    test "runtime error raises with formatted exception" do
      assert_raise RuntimeError, ~r/ArithmeticError/, fn ->
        call(%{title: "divzero", code: "1 / 0"})
      end
    end

    test "error includes partial output" do
      assert_raise RuntimeError, ~r/before/, fn ->
        call(%{
          title: "partial",
          code: ~S"""
          IO.puts("before")
          raise "boom"
          """
        })
      end
    end

    test "timeout raises with descriptive message" do
      assert_raise RuntimeError, ~r/timed out/i, fn ->
        call(%{title: "slow", code: "Process.sleep(:infinity)"}, timeout: 500)
      end
    end

    test "timeout includes partial output" do
      assert_raise RuntimeError, ~r/before sleep/, fn ->
        call(
          %{
            title: "slow",
            code: ~S"""
            IO.puts("before sleep")
            Process.sleep(:infinity)
            """
          },
          timeout: 500
        )
      end
    end

    test "node crash raises with descriptive message" do
      assert_raise RuntimeError, ~r/crashed/i, fn ->
        call(%{title: "crash", code: "System.halt(1)"})
      end
    end
  end

  describe "init/1" do
    test "defaults to empty opts when given nil" do
      tool = Tool.new()
      assert tool.name == "repl"
    end

    test "passes through timeout and max_output" do
      tool = Tool.new(timeout: 5_000, max_output: 1_000)
      assert tool.name == "repl"
    end

    test "strips unrecognised keys" do
      tool = Tool.new(session_id: "abc", foo: :bar, timeout: 5_000)
      assert tool.name == "repl"
    end
  end
end
