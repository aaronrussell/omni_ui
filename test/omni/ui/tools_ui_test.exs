defmodule Omni.UI.ToolsUITest do
  use Omni.UI.ComponentCase, async: true

  import Omni.UI.ToolsUI
  alias Omni.Content

  defp files_use(command, opts \\ []) do
    id = Keyword.get(opts, :id, "tc1")
    filename = Keyword.get(opts, :filename, "notes.md")

    input =
      case command do
        "list" -> %{"command" => "list"}
        cmd -> %{"command" => cmd, "id" => filename}
      end

    %Content.ToolUse{id: id, name: "files", input: input}
  end

  defp tool_result(opts \\ []) do
    %Content.ToolResult{
      tool_use_id: Keyword.get(opts, :id, "tc1"),
      name: "files",
      is_error: Keyword.get(opts, :is_error, false),
      content: [%Content.Text{text: Keyword.get(opts, :text, "ok")}]
    }
  end

  # ── files_tool_use/1 ─────────────────────────────────────────────

  describe "files_tool_use/1" do
    test "renders tool name" do
      assigns = %{tu: files_use("read")}

      html =
        rendered_to_string(~H"""
        <.files_tool_use tool_use={@tu} />
        """)

      assert html =~ "files"
    end

    test "write command shows open button with filename" do
      assigns = %{tu: files_use("write", filename: "app.ex"), tr: tool_result()}

      html =
        rendered_to_string(~H"""
        <.files_tool_use tool_use={@tu} tool_result={@tr} />
        """)

      assert html =~ ~s(phx-click="open_file")
      assert html =~ "app.ex"
    end

    test "patch command shows open button with filename" do
      assigns = %{tu: files_use("patch", filename: "lib.ex"), tr: tool_result()}

      html =
        rendered_to_string(~H"""
        <.files_tool_use tool_use={@tu} tool_result={@tr} />
        """)

      assert html =~ ~s(phx-click="open_file")
      assert html =~ "lib.ex"
    end

    test "read command shows read label with filename" do
      assigns = %{tu: files_use("read", filename: "config.exs"), tr: tool_result()}

      html =
        rendered_to_string(~H"""
        <.files_tool_use tool_use={@tu} tool_result={@tr} />
        """)

      assert html =~ "Read"
      assert html =~ "config.exs"
      refute html =~ ~s(phx-click="open_file")
    end

    test "list command shows listed label" do
      assigns = %{tu: files_use("list"), tr: tool_result()}

      html =
        rendered_to_string(~H"""
        <.files_tool_use tool_use={@tu} tool_result={@tr} />
        """)

      assert html =~ "Listed files"
    end

    test "delete command shows deleted label with filename" do
      assigns = %{tu: files_use("delete", filename: "old.txt"), tr: tool_result()}

      html =
        rendered_to_string(~H"""
        <.files_tool_use tool_use={@tu} tool_result={@tr} />
        """)

      assert html =~ "Deleted"
      assert html =~ "old.txt"
    end

    test "hides aside when no tool_result" do
      assigns = %{tu: files_use("write")}

      html =
        rendered_to_string(~H"""
        <.files_tool_use tool_use={@tu} />
        """)

      refute html =~ ~s(phx-click="open_file")
      refute html =~ "Listed files"
    end
  end

  # ── repl_tool_use/1 ─────────────────────────────────────────────

  describe "repl_tool_use/1" do
    defp repl_use(opts \\ []) do
      input =
        %{"code" => Keyword.get(opts, :code, ~s[IO.puts("hi")])}
        |> then(fn m ->
          if title = Keyword.get(opts, :title),
            do: Map.put(m, "title", title),
            else: m
        end)

      %Content.ToolUse{
        id: Keyword.get(opts, :id, "tc1"),
        name: "repl",
        input: input
      }
    end

    test "renders custom title from input" do
      assigns = %{tu: repl_use(title: "Check version")}

      html =
        rendered_to_string(~H"""
        <.repl_tool_use tool_use={@tu} />
        """)

      assert html =~ "Check version"
    end

    test "renders default title when none given" do
      assigns = %{tu: repl_use()}

      html =
        rendered_to_string(~H"""
        <.repl_tool_use tool_use={@tu} />
        """)

      assert html =~ "Running code"
    end

    test "renders code block" do
      assigns = %{tu: repl_use(code: "1 + 1")}

      html =
        rendered_to_string(~H"""
        <.repl_tool_use tool_use={@tu} />
        """)

      assert html =~ "Code"
      assert html =~ "language-elixir"
    end

    test "shows streaming indicator" do
      assigns = %{tu: repl_use()}

      html =
        rendered_to_string(~H"""
        <.repl_tool_use tool_use={@tu} streaming={true} />
        """)

      assert html =~ "animate-(--busy-animation)"
    end

    test "shows success check when result is not error" do
      assigns = %{tu: repl_use(), tr: tool_result()}

      html =
        rendered_to_string(~H"""
        <.repl_tool_use tool_use={@tu} tool_result={@tr} />
        """)

      assert html =~ "text-green-500"
    end

    test "shows error icon when result is error" do
      assigns = %{tu: repl_use(), tr: tool_result(is_error: true)}

      html =
        rendered_to_string(~H"""
        <.repl_tool_use tool_use={@tu} tool_result={@tr} />
        """)

      assert html =~ "text-red-500"
    end

    test "renders output section when result present" do
      assigns = %{tu: repl_use(), tr: tool_result(text: "result data")}

      html =
        rendered_to_string(~H"""
        <.repl_tool_use tool_use={@tu} tool_result={@tr} />
        """)

      assert html =~ "Output:"
      assert html =~ "result data"
    end

    test "hides output section when no result" do
      assigns = %{tu: repl_use()}

      html =
        rendered_to_string(~H"""
        <.repl_tool_use tool_use={@tu} />
        """)

      refute html =~ "Output:"
    end

    test "error result has red ring class" do
      assigns = %{tu: repl_use(), tr: tool_result(is_error: true, text: "** (RuntimeError)")}

      html =
        rendered_to_string(~H"""
        <.repl_tool_use tool_use={@tu} tool_result={@tr} />
        """)

      assert html =~ "ring-red-500"
    end

    test "renders json input when no code key" do
      tu = %Content.ToolUse{id: "tc1", name: "repl", input: %{"expr" => "1+1"}}
      assigns = %{tu: tu}

      html =
        rendered_to_string(~H"""
        <.repl_tool_use tool_use={@tu} />
        """)

      assert html =~ "Input"
      assert html =~ "expr"
    end
  end
end
