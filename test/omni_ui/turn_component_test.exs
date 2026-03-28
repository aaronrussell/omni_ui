defmodule OmniUI.TurnComponentTest do
  use OmniUI.ComponentCase, async: true

  alias OmniUI.{Turn, TurnComponent}
  alias Omni.{Content, Usage}

  defp simple_turn do
    %Turn{
      id: 1,
      res_id: 2,
      status: :complete,
      edits: [1],
      regens: [2],
      user_text: [%Content.Text{text: "Hello there"}],
      user_attachments: [],
      user_timestamp: ~U[2026-01-15 10:00:00Z],
      content: [%Content.Text{text: "Hi! How can I help?"}],
      tool_results: %{},
      usage: %Usage{input_tokens: 50, output_tokens: 30}
    }
  end

  defp branching_turn do
    %{simple_turn() | edits: [1, 3], regens: [2, 4]}
  end

  defp streaming_turn do
    %{simple_turn() | status: :streaming, res_id: nil, regens: []}
  end

  describe "render (normal turn)" do
    test "renders user message text" do
      html = render_component(TurnComponent, id: "turn-1", turn: simple_turn())

      assert html =~ "Hello there"
    end

    test "renders assistant message text" do
      html = render_component(TurnComponent, id: "turn-1", turn: simple_turn())

      assert html =~ "Hi! How can I help?"
    end

    test "renders timestamp" do
      html = render_component(TurnComponent, id: "turn-1", turn: simple_turn())

      assert html =~ "2026"
    end

    test "renders usage stats" do
      html = render_component(TurnComponent, id: "turn-1", turn: simple_turn())

      assert html =~ "50"
      assert html =~ "30"
    end

    test "does not show version nav when only one version" do
      html = render_component(TurnComponent, id: "turn-1", turn: simple_turn())

      # sibling_pos produces "1/1" only when rendered, but version_nav
      # is guarded by length > 1, so no chevrons should appear
      refute html =~ "chevron"
    end

    test "does not show edit form in normal mode" do
      html = render_component(TurnComponent, id: "turn-1", turn: simple_turn())

      refute html =~ "Editing this message"
    end
  end

  describe "render (branching)" do
    test "shows version nav when multiple edits exist" do
      html = render_component(TurnComponent, id: "turn-1", turn: branching_turn())

      assert html =~ "1/2"
    end

    test "shows version nav when multiple regens exist" do
      html = render_component(TurnComponent, id: "turn-1", turn: branching_turn())

      # Should appear twice: once for edits, once for regens
      assert html =~ "1/2"
    end
  end

  describe "render (streaming)" do
    test "does not render assistant actions while streaming" do
      html = render_component(TurnComponent, id: "turn-1", turn: streaming_turn())

      # The regenerate button should not appear during streaming
      refute html =~ "regenerate"
    end

    test "still renders user message while streaming" do
      html = render_component(TurnComponent, id: "turn-1", turn: streaming_turn())

      assert html =~ "Hello there"
    end
  end

  describe "render (tool use)" do
    test "renders tool use content block" do
      turn = %{
        simple_turn()
        | content: [
            %Content.ToolUse{id: "tc1", name: "search", input: %{"query" => "test"}},
            %Content.Text{text: "Found it"}
          ],
          tool_results: %{
            "tc1" => %Content.ToolResult{
              tool_use_id: "tc1",
              name: "search",
              content: [%Content.Text{text: "result data"}]
            }
          }
      }

      html = render_component(TurnComponent, id: "turn-1", turn: turn)

      assert html =~ "search"
      assert html =~ "Found it"
    end
  end
end
