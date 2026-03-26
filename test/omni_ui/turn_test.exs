defmodule OmniUI.TurnTest do
  use ExUnit.Case, async: true

  alias OmniUI.{Tree, Turn}
  alias Omni.{Content, Message, Usage}

  defp msg(text), do: Message.new(text)
  defp assistant(text), do: Message.new(role: :assistant, content: text)

  defp usage(input, output), do: %Usage{input_tokens: input, output_tokens: output}

  defp tool_use(id, name) do
    %Content.ToolUse{id: id, name: name, input: %{}}
  end

  defp tool_result(tool_use_id, text) do
    %Content.ToolResult{
      tool_use_id: tool_use_id,
      name: "tool",
      content: [%Content.Text{text: text}]
    }
  end

  defp tool_result_message(tool_use_id, text) do
    Message.new(role: :user, content: [tool_result(tool_use_id, text)])
  end

  describe "new/3" do
    test "builds a turn from a simple user + assistant exchange" do
      messages = [msg("hello"), assistant("hi there")]
      turn = Turn.new(1, messages, usage(10, 20))

      assert turn.id == 1
      assert turn.status == :complete
      assert [%Content.Text{text: "hello"}] = turn.user_text
      assert turn.user_attachments == []
      assert [%Content.Text{text: "hi there"}] = turn.content
      assert turn.usage == usage(10, 20)
    end

    test "collects tool results from intermediate user messages" do
      messages = [
        msg("do something"),
        Message.new(role: :assistant, content: [tool_use("tc1", "search")]),
        tool_result_message("tc1", "result data"),
        assistant("here's what I found")
      ]

      turn = Turn.new(1, messages, %Usage{})

      assert Map.has_key?(turn.tool_results, "tc1")
      assert turn.tool_results["tc1"].tool_use_id == "tc1"
    end

    test "accumulates content from multiple assistant messages" do
      messages = [
        msg("question"),
        Message.new(role: :assistant, content: [tool_use("tc1", "lookup")]),
        tool_result_message("tc1", "data"),
        assistant("final answer")
      ]

      turn = Turn.new(1, messages, %Usage{})

      assert length(turn.content) == 2
      assert %Content.ToolUse{id: "tc1"} = hd(turn.content)
      assert %Content.Text{text: "final answer"} = List.last(turn.content)
    end

    test "sets timestamp from last assistant message" do
      now = DateTime.utc_now()

      messages = [
        msg("hello"),
        %{assistant("first") | timestamp: ~U[2026-01-01 00:00:00Z]},
        %{assistant("second") | timestamp: now}
      ]

      turn = Turn.new(1, messages, %Usage{})

      assert turn.timestamp == now
    end

    test "defaults edits, regens, and res_id" do
      turn = Turn.new(1, [msg("hi"), assistant("hey")], %Usage{})

      assert turn.edits == []
      assert turn.regens == []
      assert turn.res_id == nil
    end
  end

  describe "all/1" do
    test "empty tree returns empty list" do
      assert Turn.all(%Tree{}) == []
    end

    test "simple two-message turn" do
      tree =
        %Tree{}
        |> Tree.push(msg("hello"))
        |> Tree.push(assistant("hi"), usage(10, 20))

      [turn] = Turn.all(tree)

      assert turn.id == 1
      assert turn.res_id == 2
      assert [%Content.Text{text: "hello"}] = turn.user_text
      assert [%Content.Text{text: "hi"}] = turn.content
      assert turn.usage == usage(10, 20)
    end

    test "multi-turn conversation produces correct number of turns" do
      tree =
        %Tree{}
        |> Tree.push(msg("first"))
        |> Tree.push(assistant("response 1"), usage(10, 20))
        |> Tree.push(msg("second"))
        |> Tree.push(assistant("response 2"), usage(30, 40))

      turns = Turn.all(tree)

      assert length(turns) == 2
      assert [%{id: 1}, %{id: 3}] = turns
    end

    test "tool-use turn is chunked as a single turn" do
      tree =
        %Tree{}
        |> Tree.push(msg("search for X"))
        |> Tree.push(Message.new(role: :assistant, content: [tool_use("tc1", "search")]))
        |> Tree.push(tool_result_message("tc1", "found it"))
        |> Tree.push(assistant("here's what I found"), usage(50, 60))

      [turn] = Turn.all(tree)

      assert turn.id == 1
      assert Map.has_key?(turn.tool_results, "tc1")
      assert length(turn.content) == 2
    end

    test "edits are populated when user messages share a parent" do
      tree =
        %Tree{}
        |> Tree.push(msg("hello"))
        |> Tree.push(assistant("hi"), usage(10, 20))
        |> Tree.push(msg("follow-up A"))
        |> Tree.push(assistant("response A"), usage(30, 40))

      # Navigate back and create an edit
      {:ok, tree} = Tree.navigate(tree, 2)

      tree =
        tree
        |> Tree.push(msg("follow-up B"))
        |> Tree.push(assistant("response B"), usage(30, 40))

      # Navigate back to the original path
      {:ok, tree} = Tree.navigate(tree, 4)

      turns = Turn.all(tree)
      turn_2 = Enum.at(turns, 1)

      assert turn_2.id == 3
      assert turn_2.edits == [3, 5]
    end

    test "regens are populated when assistant messages share a parent" do
      tree =
        %Tree{}
        |> Tree.push(msg("hello"))
        |> Tree.push(assistant("response 1"), usage(10, 20))

      # Navigate back to user message and push a regen
      {:ok, tree} = Tree.navigate(tree, 1)
      tree = Tree.push(tree, assistant("response 2"), usage(15, 25))

      # Navigate back to original path
      {:ok, tree} = Tree.navigate(tree, 2)

      [turn] = Turn.all(tree)

      assert turn.res_id == 2
      assert turn.regens == [2, 3]
    end

    test "no branching produces single-element edits and regens" do
      tree =
        %Tree{}
        |> Tree.push(msg("hello"))
        |> Tree.push(assistant("hi"), usage(10, 20))

      [turn] = Turn.all(tree)

      assert turn.edits == [1]
      assert turn.regens == [2]
    end

    test "leading assistant message without a user message is skipped" do
      # If the path starts with an assistant node (edge case), it should be dropped
      {_, tree} = Tree.push_node(%Tree{}, Message.new(role: :assistant, content: "orphan"))
      {_, tree} = Tree.push_node(tree, msg("hello"))
      {_, tree} = Tree.push_node(tree, assistant("hi"))

      turns = Turn.all(tree)

      assert length(turns) == 1
      assert hd(turns).id == 2
    end
  end

  describe "all/1 with faker" do
    test "produces correct turns with edits and regens" do
      tree = OmniUI.TreeFaker.generate()
      turns = Turn.all(tree)

      assert length(turns) == 7

      # Turn at node 9 (lunch spots) should have both an edit and a regen
      lunch_turn = Enum.find(turns, &(&1.id == 9))
      assert lunch_turn.edits == [9, 25]
      assert lunch_turn.regens == [10, 29]
      assert lunch_turn.res_id == 10

      # All other turns should have single-element edits and regens
      other_turns = Enum.reject(turns, &(&1.id == 9))

      for turn <- other_turns do
        assert length(turn.edits) == 1, "turn #{turn.id} should have 1 edit"
        assert length(turn.regens) == 1, "turn #{turn.id} should have 1 regen"
      end
    end

    test "turn IDs match the first user message node in each turn" do
      tree = OmniUI.TreeFaker.generate()
      turns = Turn.all(tree)

      ids = Enum.map(turns, & &1.id)
      assert ids == [1, 3, 9, 11, 17, 21, 23]
    end

    test "res_id matches the first assistant message node in each turn" do
      tree = OmniUI.TreeFaker.generate()
      turns = Turn.all(tree)

      res_ids = Enum.map(turns, & &1.res_id)
      assert res_ids == [2, 4, 10, 12, 18, 22, 24]
    end
  end

  describe "get/2" do
    test "returns a single turn for a simple exchange" do
      tree =
        %Tree{}
        |> Tree.push(msg("hello"))
        |> Tree.push(assistant("hi"), usage(10, 20))

      turn = Turn.get(tree, 1)

      assert turn.id == 1
      assert turn.res_id == 2
      assert [%Content.Text{text: "hello"}] = turn.user_text
      assert [%Content.Text{text: "hi"}] = turn.content
      assert turn.usage == usage(10, 20)
    end

    test "returns correct turn from a multi-turn conversation" do
      tree =
        %Tree{}
        |> Tree.push(msg("first"))
        |> Tree.push(assistant("response 1"), usage(10, 20))
        |> Tree.push(msg("second"))
        |> Tree.push(assistant("response 2"), usage(30, 40))

      turn = Turn.get(tree, 3)

      assert turn.id == 3
      assert turn.res_id == 4
      assert [%Content.Text{text: "second"}] = turn.user_text
      assert [%Content.Text{text: "response 2"}] = turn.content
      assert turn.usage == usage(30, 40)
    end

    test "includes tool-use nodes within the turn" do
      tree =
        %Tree{}
        |> Tree.push(msg("search for X"))
        |> Tree.push(Message.new(role: :assistant, content: [tool_use("tc1", "search")]))
        |> Tree.push(tool_result_message("tc1", "found it"))
        |> Tree.push(assistant("here's what I found"), usage(50, 60))

      turn = Turn.get(tree, 1)

      assert turn.id == 1
      assert Map.has_key?(turn.tool_results, "tc1")
      assert length(turn.content) == 2
    end

    test "does not bleed into the next turn" do
      tree =
        %Tree{}
        |> Tree.push(msg("first"))
        |> Tree.push(assistant("response 1"), usage(10, 20))
        |> Tree.push(msg("second"))
        |> Tree.push(assistant("response 2"), usage(30, 40))

      turn = Turn.get(tree, 1)

      assert turn.id == 1
      assert [%Content.Text{text: "response 1"}] = turn.content
    end

    test "populates edits and regens" do
      tree =
        %Tree{}
        |> Tree.push(msg("hello"))
        |> Tree.push(assistant("response 1"), usage(10, 20))

      {:ok, tree} = Tree.navigate(tree, 1)
      tree = Tree.push(tree, assistant("response 2"), usage(15, 25))
      {:ok, tree} = Tree.navigate(tree, 2)

      turn = Turn.get(tree, 1)

      assert turn.regens == [2, 3]
    end

    test "matches all/1 output for each turn" do
      tree = OmniUI.TreeFaker.generate()
      all_turns = Turn.all(tree)

      for expected <- all_turns do
        got = Turn.get(tree, expected.id)
        assert got == expected
      end
    end
  end

  describe "push_content/2" do
    test "appends a content block" do
      turn = Turn.new(1, [msg("hi"), assistant("hey")], %Usage{})
      turn = Turn.push_content(turn, %Content.Text{text: "more"})

      assert length(turn.content) == 2
      assert %Content.Text{text: "more"} = List.last(turn.content)
    end
  end

  describe "push_delta/2" do
    test "appends delta text to the last content block" do
      turn = Turn.new(1, [msg("hi"), assistant("hey")], %Usage{})
      turn = Turn.push_content(turn, %Content.Text{text: "hello"})
      turn = Turn.push_delta(turn, " world")

      assert %Content.Text{text: "hello world"} = List.last(turn.content)
    end

    test "does not affect earlier content blocks" do
      turn = Turn.new(1, [msg("hi"), assistant("hey")], %Usage{})
      turn = Turn.push_content(turn, %Content.Thinking{text: "thinking"})
      turn = Turn.push_content(turn, %Content.Text{text: "start"})
      turn = Turn.push_delta(turn, " more")

      assert %Content.Thinking{text: "thinking"} = Enum.at(turn.content, 1)
      assert %Content.Text{text: "start more"} = List.last(turn.content)
    end
  end

  describe "put_tool_result/2" do
    test "stores tool result keyed by tool_use_id" do
      turn = Turn.new(1, [msg("hi"), assistant("hey")], %Usage{})
      result = tool_result("tc1", "data")
      turn = Turn.put_tool_result(turn, result)

      assert turn.tool_results["tc1"] == result
    end

    test "multiple tool results are stored independently" do
      turn = Turn.new(1, [msg("hi"), assistant("hey")], %Usage{})
      turn = Turn.put_tool_result(turn, tool_result("tc1", "data1"))
      turn = Turn.put_tool_result(turn, tool_result("tc2", "data2"))

      assert map_size(turn.tool_results) == 2
      assert turn.tool_results["tc1"].tool_use_id == "tc1"
      assert turn.tool_results["tc2"].tool_use_id == "tc2"
    end
  end
end
