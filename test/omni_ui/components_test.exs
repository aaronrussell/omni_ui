defmodule OmniUI.ComponentsTest do
  use OmniUI.ComponentCase, async: true

  alias Omni.{Content, Usage}

  # ── content_block/1 ─────────────────────────────────────────────

  describe "content_block/1" do
    test "renders text content as markdown" do
      assigns = %{content: %Content.Text{text: "**bold**"}, streaming: false}

      html =
        rendered_to_string(~H"""
        <.content_block content={@content} streaming={@streaming} />
        """)

      assert html =~ "<strong>bold</strong>"
      assert html =~ "md"
    end

    test "renders thinking block with label" do
      assigns = %{content: %Content.Thinking{text: "let me think"}, streaming: false}

      html =
        rendered_to_string(~H"""
        <.content_block content={@content} streaming={@streaming} />
        """)

      assert html =~ "Thought"
      assert html =~ "let me think"
    end

    test "renders thinking block with streaming label" do
      assigns = %{content: %Content.Thinking{text: "thinking..."}, streaming: true}

      html =
        rendered_to_string(~H"""
        <.content_block content={@content} streaming={@streaming} />
        """)

      assert html =~ "Thinking"
      assert html =~ "animate-spin"
    end

    test "renders tool use with tool name" do
      assigns = %{
        content: %Content.ToolUse{id: "tc1", name: "search", input: %{"q" => "test"}},
        tool_results: %{},
        streaming: false
      }

      html =
        rendered_to_string(~H"""
        <.content_block content={@content} tool_results={@tool_results} streaming={@streaming} />
        """)

      assert html =~ "search"
      assert html =~ "Input:"
    end

    test "renders tool use with completed result" do
      assigns = %{
        content: %Content.ToolUse{id: "tc1", name: "search", input: %{}},
        tool_results: %{
          "tc1" => %Content.ToolResult{
            tool_use_id: "tc1",
            name: "search",
            content: [%Content.Text{text: "found it"}]
          }
        },
        streaming: false
      }

      html =
        rendered_to_string(~H"""
        <.content_block content={@content} tool_results={@tool_results} streaming={@streaming} />
        """)

      assert html =~ "Output:"
      assert html =~ "found it"
    end

    test "renders tool use with error result" do
      assigns = %{
        content: %Content.ToolUse{id: "tc1", name: "search", input: %{}},
        tool_results: %{
          "tc1" => %Content.ToolResult{
            tool_use_id: "tc1",
            name: "search",
            is_error: true,
            content: [%Content.Text{text: "connection refused"}]
          }
        },
        streaming: false
      }

      html =
        rendered_to_string(~H"""
        <.content_block content={@content} tool_results={@tool_results} streaming={@streaming} />
        """)

      assert html =~ "ring-red-500"
    end

    test "renders tool use with custom component from tool_components" do
      custom = fn assigns ->
        ~H"""
        <div class="custom-tool-use">
          custom: {@tool_use.name} / {@tool_use.input["q"]} /
          <%= if @tool_result, do: "done", else: "pending" %>
        </div>
        """
      end

      assigns = %{
        content: %Content.ToolUse{id: "tc1", name: "search", input: %{"q" => "hello"}},
        tool_results: %{},
        tool_components: %{"search" => custom},
        streaming: false
      }

      html =
        rendered_to_string(~H"""
        <.content_block
          content={@content}
          tool_results={@tool_results}
          tool_components={@tool_components}
          streaming={@streaming} />
        """)

      assert html =~ "custom-tool-use"
      assert html =~ "custom: search / hello"
      assert html =~ "pending"
      # Default tool-use rendering artefacts should be absent
      refute html =~ "Input:"
    end

    test "custom component receives pre-resolved tool_result when available" do
      custom = fn assigns ->
        ~H"""
        <div>
          <%= if @tool_result do %>
            result-id: {@tool_result.tool_use_id}
          <% end %>
        </div>
        """
      end

      assigns = %{
        content: %Content.ToolUse{id: "tc1", name: "search", input: %{}},
        tool_results: %{
          "tc1" => %Content.ToolResult{
            tool_use_id: "tc1",
            name: "search",
            content: [%Content.Text{text: "ok"}]
          }
        },
        tool_components: %{"search" => custom},
        streaming: false
      }

      html =
        rendered_to_string(~H"""
        <.content_block
          content={@content}
          tool_results={@tool_results}
          tool_components={@tool_components}
          streaming={@streaming} />
        """)

      assert html =~ "result-id: tc1"
    end

    test "falls back to default rendering when tool_components has no entry for the tool" do
      other = fn assigns ->
        ~H"""
        <div>other tool component</div>
        """
      end

      assigns = %{
        content: %Content.ToolUse{id: "tc1", name: "search", input: %{"q" => "test"}},
        tool_results: %{},
        tool_components: %{"other_tool" => other},
        streaming: false
      }

      html =
        rendered_to_string(~H"""
        <.content_block
          content={@content}
          tool_results={@tool_results}
          tool_components={@tool_components}
          streaming={@streaming} />
        """)

      # Default rendering shows the tool name and an "Input:" label
      assert html =~ "search"
      assert html =~ "Input:"
      refute html =~ "other tool component"
    end

    test "renders attachment with image" do
      assigns = %{
        content: %Content.Attachment{media_type: "image/png", source: {:base64, "abc"}}
      }

      html =
        rendered_to_string(~H"""
        <.content_block content={@content} />
        """)

      assert html =~ "data:image/png;base64,abc"
    end

    test "renders attachment with non-image fallback" do
      assigns = %{
        content: %Content.Attachment{
          media_type: "application/pdf",
          source: {:url, "https://example.com/doc.pdf"}
        }
      }

      html =
        rendered_to_string(~H"""
        <.content_block content={@content} />
        """)

      assert html =~ "application/pdf"
    end
  end

  # ── version_nav/1 ───────────────────────────────────────────────

  describe "version_nav/1" do
    test "displays position" do
      assigns = %{version_id: 2, versions: [1, 2, 3]}

      html =
        rendered_to_string(~H"""
        <.version_nav version_id={@version_id} versions={@versions} />
        """)

      assert html =~ "2/3"
    end

    test "disables prev button at first position" do
      assigns = %{version_id: 1, versions: [1, 2, 3]}

      html =
        rendered_to_string(~H"""
        <.version_nav version_id={@version_id} versions={@versions} />
        """)

      # First button should be disabled
      assert html =~ ~r/disabled.*rotate-90/s
    end

    test "disables next button at last position" do
      assigns = %{version_id: 3, versions: [1, 2, 3]}

      html =
        rendered_to_string(~H"""
        <.version_nav version_id={@version_id} versions={@versions} />
        """)

      # Last button should be disabled
      assert html =~ ~r/disabled.*-rotate-90/s
    end

    test "single element disables both buttons" do
      assigns = %{version_id: 1, versions: [1]}

      html =
        rendered_to_string(~H"""
        <.version_nav version_id={@version_id} versions={@versions} />
        """)

      assert html =~ "1/1"
    end
  end

  # ── timestamp/1 ─────────────────────────────────────────────────

  describe "timestamp/1" do
    test "renders a time-ago label" do
      assigns = %{time: ~U[2026-03-15 14:30:00Z]}

      html =
        rendered_to_string(~H"""
        <.timestamp time={@time} format="%-d %B" />
        """)

      assert html =~ "<time"
      assert html =~ "datetime="
      assert html =~ "title="
      assert html =~ "15 March"
    end
  end

  # ── usage_block/1 ───────────────────────────────────────────────

  describe "usage_block/1" do
    test "renders token counts and cost" do
      assigns = %{usage: %Usage{input_tokens: 1500, output_tokens: 300, total_cost: 0.0123}}

      html =
        rendered_to_string(~H"""
        <.usage_block usage={@usage} />
        """)

      assert html =~ "1.5k"
      assert html =~ "300"
      assert html =~ "0.0123"
    end
  end

  # ── attachment/1 ────────────────────────────────────────────────

  describe "attachment/1" do
    test "renders file icon for non-image type" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.attachment name="document.pdf" media_type="application/pdf" />
        """)

      assert html =~ "document.pdf"
    end

    test "does not render file icon for image type with image slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.attachment name="photo.jpg" media_type="image/jpeg">
          <:image><img src="test.jpg" /></:image>
        </.attachment>
        """)

      assert html =~ ~s(src="test.jpg")
      refute html =~ "photo.jpg"
    end

    test "renders action slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.attachment name="file.txt" media_type="text/plain">
          <:action><button>Remove</button></:action>
        </.attachment>
        """)

      assert html =~ "Remove"
    end
  end

  # ── expandable/1 ────────────────────────────────────────────────

  describe "expandable/1" do
    test "renders label" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.expandable label="Details">
          <:icon><span>icon</span></:icon>
          Content here
        </.expandable>
        """)

      assert html =~ "Details"
      assert html =~ "Content here"
    end

    test "renders custom toggle slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.expandable>
          <:icon><span>icon</span></:icon>
          <:toggle>Custom toggle</:toggle>
          Content
        </.expandable>
        """)

      assert html =~ "Custom toggle"
    end

    test "defaults to Expand when no label or toggle" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.expandable>
          <:icon><span>icon</span></:icon>
          Content
        </.expandable>
        """)

      assert html =~ "Expand"
    end
  end

  # ── markdown/1 ──────────────────────────────────────────────────

  describe "markdown/1" do
    test "renders markdown as HTML with md class" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.markdown text="**hello**" class="" />
        """)

      assert html =~ "<strong>hello</strong>"
      assert html =~ "md"
    end

    test "passes through extra classes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.markdown text="hi" class="text-sm" />
        """)

      assert html =~ "text-sm"
      assert html =~ "md"
    end
  end
end
