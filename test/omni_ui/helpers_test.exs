defmodule OmniUI.HelpersTest do
  use ExUnit.Case, async: true
  doctest OmniUI.Helpers

  alias OmniUI.Helpers

  # ── attachment_url/1 ──────────────────────────────────────────────

  describe "attachment_url/1" do
    test "returns a data URI for base64 attachments" do
      attachment = %Omni.Content.Attachment{
        media_type: "image/png",
        source: {:base64, "abc123"}
      }

      assert Helpers.attachment_url(attachment) == "data:image/png;base64,abc123"
    end

    test "returns the URL for url-sourced attachments" do
      attachment = %Omni.Content.Attachment{
        media_type: "image/jpeg",
        source: {:url, "https://example.com/photo.jpg"}
      }

      assert Helpers.attachment_url(attachment) == "https://example.com/photo.jpg"
    end
  end

  # ── cls/1 ─────────────────────────────────────────────────────────

  describe "cls/1" do
    test "returns a string as-is" do
      assert Helpers.cls("foo bar") == "foo bar"
    end

    test "filters nil and false from lists" do
      assert Helpers.cls(["a", nil, "b", false, "c"]) == "a b c"
    end

    test "returns empty string for all-falsy list" do
      assert Helpers.cls([nil, false]) == ""
    end

    test "returns empty string for empty list" do
      assert Helpers.cls([]) == ""
    end

    test "includes map keys with truthy values" do
      result = Helpers.cls(%{"active" => true, "hidden" => false, "bold" => true})
      classes = String.split(result, " ") |> Enum.sort()
      assert classes == ["active", "bold"]
    end

    test "returns empty string for map with all falsy values" do
      assert Helpers.cls(%{"a" => false, "b" => nil}) == ""
    end

    test "returns empty string for empty map" do
      assert Helpers.cls(%{}) == ""
    end
  end

  # ── format_json/1 ────────────────────────────────────────────────

  describe "format_json/1" do
    test "pretty-prints a valid JSON string" do
      assert Helpers.format_json(~s|{"a":1}|) == "{\n  \"a\": 1\n}"
    end

    test "returns non-JSON strings unchanged" do
      assert Helpers.format_json("just text") == "just text"
    end

    test "pretty-prints a map" do
      assert Helpers.format_json(%{"key" => "value"}) == "{\n  \"key\": \"value\"\n}"
    end

    test "falls back to inspect for non-encodable data" do
      assert Helpers.format_json({:tuple, "value"}) == ~s|{:tuple, "value"}|
    end
  end

  # ── format_tool_result/1 ─────────────────────────────────────────

  describe "format_tool_result/1" do
    test "extracts and formats text content" do
      result = %Omni.Content.ToolResult{
        tool_use_id: "tool_1",
        name: "search",
        content: [%Omni.Content.Text{text: ~s|{"ok":true}|}]
      }

      assert Helpers.format_tool_result(result) == "{\n  \"ok\": true\n}"
    end

    test "joins multiple text blocks" do
      result = %Omni.Content.ToolResult{
        tool_use_id: "tool_1",
        name: "search",
        content: [
          %Omni.Content.Text{text: "line1"},
          %Omni.Content.Text{text: "line2"}
        ]
      }

      assert Helpers.format_tool_result(result) == "line1\nline2"
    end

    test "filters out non-text content" do
      result = %Omni.Content.ToolResult{
        tool_use_id: "tool_1",
        name: "search",
        content: [
          %Omni.Content.Attachment{media_type: "image/png", source: {:base64, "data"}},
          %Omni.Content.Text{text: "hello"}
        ]
      }

      assert Helpers.format_tool_result(result) == "hello"
    end
  end

  # ── format_token_count/1 ─────────────────────────────────────────

  describe "format_token_count/1" do
    test "returns raw count under 1000" do
      assert Helpers.format_token_count(0) == "0"
      assert Helpers.format_token_count(999) == "999"
    end

    test "formats with one decimal for 1k-9.9k" do
      assert Helpers.format_token_count(1_000) == "1.0k"
      assert Helpers.format_token_count(1_500) == "1.5k"
      assert Helpers.format_token_count(9_999) == "10.0k"
    end

    test "rounds to nearest k for 10k+" do
      assert Helpers.format_token_count(10_000) == "10k"
      assert Helpers.format_token_count(42_000) == "42k"
      assert Helpers.format_token_count(42_499) == "42k"
      assert Helpers.format_token_count(42_500) == "43k"
    end

    test "returns dash for nil" do
      assert Helpers.format_token_count(nil) == "-"
    end
  end

  # ── format_token_cost/1 ──────────────────────────────────────────

  describe "format_token_cost/1" do
    test "formats float to 4 decimal places" do
      assert Helpers.format_token_cost(0.0123) == "0.0123"
    end

    test "pads to 4 decimal places" do
      assert Helpers.format_token_cost(1.5) == "1.5000"
    end

    test "handles zero" do
      assert Helpers.format_token_cost(0) == "0.0000"
    end

    test "handles integer input" do
      assert Helpers.format_token_cost(3) == "3.0000"
    end

    test "returns dash for nil" do
      assert Helpers.format_token_cost(nil) == "-"
    end
  end

  # ── sibling_pos/2 ────────────────────────────────────────────────

  describe "sibling_pos/2" do
    test "returns 1-indexed position" do
      assert Helpers.sibling_pos(:b, [:a, :b, :c]) == "2/3"
    end

    test "handles first element" do
      assert Helpers.sibling_pos(:a, [:a, :b]) == "1/2"
    end

    test "handles single element" do
      assert Helpers.sibling_pos(:x, [:x]) == "1/1"
    end
  end

  # ── format_model_options/1 ────────────────────────────────────────

  describe "format_model_options/1" do
    test "returns nil for nil" do
      assert Helpers.format_model_options(nil) == nil
    end

    test "returns nil for empty list" do
      assert Helpers.format_model_options([]) == nil
    end

    test "groups models by provider and sorts alphabetically" do
      {:ok, models} = Omni.list_models(:anthropic)
      result = Helpers.format_model_options(models)

      assert [%{label: "Anthropic", options: options}] = result
      labels = Enum.map(options, & &1.label)
      assert labels == Enum.sort(labels)
    end

    test "option values use model_key format" do
      {:ok, [model | _]} = Omni.list_models(:anthropic)

      [%{options: [%{value: value} | _]}] = Helpers.format_model_options([model])

      assert value == Helpers.model_key(model)
    end
  end

  # ── find_option_label/2 ─────────────────────────────────────────

  describe "find_option_label/2" do
    test "finds label in flat options" do
      options = [%{value: "a", label: "Alpha"}, %{value: "b", label: "Beta"}]

      assert Helpers.find_option_label(options, "b") == "Beta"
    end

    test "finds label in grouped options" do
      options = [
        %{label: "Group 1", options: [%{value: "x", label: "X-ray"}]},
        %{label: "Group 2", options: [%{value: "y", label: "Yankee"}]}
      ]

      assert Helpers.find_option_label(options, "y") == "Yankee"
    end

    test "returns nil when value not found" do
      options = [%{value: "a", label: "Alpha"}]

      assert Helpers.find_option_label(options, "z") == nil
    end
  end

  # ── to_md/1 ──────────────────────────────────────────────────────

  describe "to_md/1" do
    test "converts markdown to HTML" do
      result = Helpers.to_md("**bold**")
      {:safe, html} = result
      assert html =~ "<strong>bold</strong>"
    end

    test "returns a Phoenix.HTML safe tuple" do
      assert {:safe, _} = Helpers.to_md("hello")
    end

    test "accepts streaming option" do
      assert {:safe, _} = Helpers.to_md("hello", streaming: true)
      assert {:safe, _} = Helpers.to_md("hello", streaming: false)
    end
  end
end
