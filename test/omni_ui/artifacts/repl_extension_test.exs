defmodule OmniUI.Artifacts.REPLExtensionTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 120_000
  @moduletag :tmp_dir

  alias OmniUI.Artifacts.{Artifact, FileSystem, REPLExtension}
  alias OmniUI.REPL.Sandbox

  defp ext_opts(ctx), do: [session_id: "test", base_path: ctx.tmp_dir]
  defp dir(ctx), do: FileSystem.artifacts_dir(ext_opts(ctx))

  defp run_in_sandbox(ctx, code) do
    setup = REPLExtension.code(ext_opts(ctx))
    Sandbox.run(code, setup: setup)
  end

  describe "code/1" do
    test "returns valid AST", ctx do
      ast = REPLExtension.code(ext_opts(ctx))
      assert is_tuple(ast)
    end

    test "requires session_id" do
      assert_raise KeyError, ~r/session_id/, fn ->
        REPLExtension.code([])
      end
    end
  end

  describe "description/1" do
    test "returns string mentioning Artifacts" do
      desc = REPLExtension.description([])
      assert desc =~ "Artifacts"
      assert desc =~ "write"
      assert desc =~ "read"
      assert desc =~ "patch"
      assert desc =~ "list"
      assert desc =~ "delete"
    end
  end

  describe "Artifacts.write/2" do
    test "creates file on disk and returns Artifact struct", ctx do
      assert {:ok, %{result: %Artifact{filename: "hello.txt"}}} =
               run_in_sandbox(ctx, ~S|Artifacts.write("hello.txt", "hi there")|)

      assert File.read!(Path.join(dir(ctx), "hello.txt")) == "hi there"
    end

    test "overwrites existing file", ctx do
      run_in_sandbox(ctx, ~S|Artifacts.write("f.txt", "v1")|)
      run_in_sandbox(ctx, ~S|Artifacts.write("f.txt", "v2")|)

      assert File.read!(Path.join(dir(ctx), "f.txt")) == "v2"
    end
  end

  describe "Artifacts.read/1" do
    test "returns content of existing file", ctx do
      FileSystem.write("data.txt", "some data", ext_opts(ctx))

      assert {:ok, %{result: "some data"}} =
               run_in_sandbox(ctx, ~S|Artifacts.read("data.txt")|)
    end

    test "raises on nonexistent file", ctx do
      assert {:error, {_kind, _reason, _stack}, _} =
               run_in_sandbox(ctx, ~S|Artifacts.read("missing.txt")|)
    end
  end

  describe "Artifacts.patch/3" do
    test "modifies file on disk", ctx do
      FileSystem.write("page.html", "<h1>Old Title</h1>", ext_opts(ctx))

      assert {:ok, %{result: %Artifact{}}} =
               run_in_sandbox(ctx, ~S|Artifacts.patch("page.html", "Old Title", "New Title")|)

      assert File.read!(Path.join(dir(ctx), "page.html")) == "<h1>New Title</h1>"
    end
  end

  describe "Artifacts.list/0" do
    test "returns list of artifact structs", ctx do
      FileSystem.write("a.txt", "a", ext_opts(ctx))
      FileSystem.write("b.txt", "b", ext_opts(ctx))

      assert {:ok, %{result: artifacts}} = run_in_sandbox(ctx, "Artifacts.list()")
      assert length(artifacts) == 2
      assert Enum.all?(artifacts, &match?(%Artifact{}, &1))
    end

    test "returns empty list when no artifacts", ctx do
      assert {:ok, %{result: []}} = run_in_sandbox(ctx, "Artifacts.list()")
    end
  end

  describe "Artifacts.delete/1" do
    test "removes file from disk", ctx do
      FileSystem.write("temp.txt", "x", ext_opts(ctx))

      assert {:ok, %{result: :ok}} =
               run_in_sandbox(ctx, ~S|Artifacts.delete("temp.txt")|)

      refute File.exists?(Path.join(dir(ctx), "temp.txt"))
    end
  end

  describe "error handling" do
    test "raises on invalid filename", ctx do
      assert {:error, {_kind, _reason, _stack}, _} =
               run_in_sandbox(ctx, ~S|Artifacts.write("../evil.txt", "x")|)
    end
  end
end
