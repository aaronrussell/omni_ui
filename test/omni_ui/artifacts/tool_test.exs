defmodule OmniUI.Artifacts.ToolTest do
  use ExUnit.Case, async: true

  alias OmniUI.Artifacts.{FileSystem, Tool}

  @moduletag :tmp_dir

  defp tool_opts(%{tmp_dir: tmp_dir}), do: [session_id: "test", base_path: tmp_dir]

  defp dir(%{tmp_dir: tmp_dir}),
    do: FileSystem.artifacts_dir(session_id: "test", base_path: tmp_dir)

  defp call(ctx, input) do
    tool = Tool.new(tool_opts(ctx))
    tool.handler.(input)
  end

  describe "schema/0" do
    test "returns a valid schema map" do
      tool = Tool.new(session_id: "unused", base_path: "/tmp")

      assert %{type: "object", properties: props, required: [:command]} = tool.input_schema
      assert %{enum: ["write", "patch", "get", "list", "delete"]} = props.command
      assert %{type: "string"} = props.filename
      assert %{type: "string"} = props.content
      assert %{type: "string"} = props.search
      assert %{type: "string"} = props.replace
    end
  end

  describe "write command" do
    test "creates artifact and returns confirmation", ctx do
      result = call(ctx, %{command: "write", filename: "test.html", content: "<p>hello</p>"})

      assert result == "Wrote test.html (#{byte_size("<p>hello</p>")} bytes)"
      assert File.read!(Path.join(dir(ctx), "test.html")) == "<p>hello</p>"
    end

    test "raises on invalid filename", ctx do
      assert_raise RuntimeError, ~r/path separators/, fn ->
        call(ctx, %{command: "write", filename: "../evil.txt", content: "x"})
      end
    end
  end

  describe "patch command" do
    test "patches file and returns confirmation", ctx do
      call(ctx, %{command: "write", filename: "page.html", content: "<h1>Old</h1>"})

      result =
        call(ctx, %{command: "patch", filename: "page.html", search: "Old", replace: "New"})

      assert result =~ "Patched page.html"
      assert File.read!(Path.join(dir(ctx), "page.html")) == "<h1>New</h1>"
    end

    test "raises when search string not found", ctx do
      call(ctx, %{command: "write", filename: "file.txt", content: "hello"})

      assert_raise RuntimeError, ~r/search string not found/, fn ->
        call(ctx, %{command: "patch", filename: "file.txt", search: "missing", replace: "x"})
      end
    end
  end

  describe "get command" do
    test "returns file content", ctx do
      call(ctx, %{command: "write", filename: "data.json", content: ~s({"key":"value"})})

      assert call(ctx, %{command: "get", filename: "data.json"}) == ~s({"key":"value"})
    end

    test "raises on missing file", ctx do
      assert_raise RuntimeError, ~r/artifact not found/, fn ->
        call(ctx, %{command: "get", filename: "nope.txt"})
      end
    end
  end

  describe "list command" do
    test "returns formatted list", ctx do
      call(ctx, %{command: "write", filename: "b.json", content: "{}"})
      call(ctx, %{command: "write", filename: "a.html", content: "<h1>hi</h1>"})

      result = call(ctx, %{command: "list"})

      assert result =~ "a.html (text/html,"
      assert result =~ "b.json (application/json,"
    end

    test "returns message when no artifacts", ctx do
      assert call(ctx, %{command: "list"}) == "No artifacts"
    end
  end

  describe "delete command" do
    test "deletes file and returns confirmation", ctx do
      call(ctx, %{command: "write", filename: "temp.txt", content: "gone"})

      assert call(ctx, %{command: "delete", filename: "temp.txt"}) == "Deleted temp.txt"
      refute File.exists?(Path.join(dir(ctx), "temp.txt"))
    end

    test "raises on missing file", ctx do
      assert_raise RuntimeError, ~r/artifact not found/, fn ->
        call(ctx, %{command: "delete", filename: "nope.txt"})
      end
    end
  end
end
