defmodule OmniUI.Artifacts.FileSystemTest do
  use ExUnit.Case, async: true

  alias OmniUI.Artifacts.{Artifact, FileSystem}

  @moduletag :tmp_dir

  defp opts(%{tmp_dir: tmp_dir}), do: [session_id: "test", base_path: tmp_dir]
  defp dir(%{tmp_dir: tmp_dir}), do: Path.join([tmp_dir, "test", "artifacts"])

  describe "artifacts_dir/1" do
    test "builds path from session_id and base_path" do
      assert FileSystem.artifacts_dir(session_id: "abc123", base_path: "/data/sessions") ==
               "/data/sessions/abc123/artifacts"
    end

    test "requires session_id" do
      assert_raise KeyError, ~r/:session_id/, fn ->
        FileSystem.artifacts_dir(base_path: "/tmp")
      end
    end

    test "falls back to default base_path when not provided" do
      dir = FileSystem.artifacts_dir(session_id: "test")
      assert dir =~ "omni/sessions/test/artifacts"
    end
  end

  describe "write/3" do
    test "creates file and returns artifact", ctx do
      assert {:ok, %Artifact{} = artifact} =
               FileSystem.write("report.html", "<h1>Hi</h1>", opts(ctx))

      assert artifact.filename == "report.html"
      assert artifact.mime_type == "text/html"
      assert artifact.size == byte_size("<h1>Hi</h1>")
      assert %DateTime{} = artifact.updated_at
      assert File.read!(Path.join(dir(ctx), "report.html")) == "<h1>Hi</h1>"
    end

    test "creates directory if it doesn't exist", ctx do
      dir = dir(ctx)
      refute File.dir?(dir)

      assert {:ok, _} = FileSystem.write("test.txt", "hello", opts(ctx))
      assert File.dir?(dir)
    end

    test "upserts — overwrites existing file", ctx do
      assert {:ok, _} = FileSystem.write("data.json", ~s({"v":1}), opts(ctx))
      assert {:ok, artifact} = FileSystem.write("data.json", ~s({"v":2}), opts(ctx))

      assert artifact.size == byte_size(~s({"v":2}))
      assert File.read!(Path.join(dir(ctx), "data.json")) == ~s({"v":2})
    end
  end

  describe "read/2" do
    test "returns file content", ctx do
      FileSystem.write("hello.txt", "world", opts(ctx))

      assert {:ok, "world"} = FileSystem.read("hello.txt", opts(ctx))
    end

    test "error on missing file", ctx do
      assert {:error, "artifact not found: nope.txt"} = FileSystem.read("nope.txt", opts(ctx))
    end
  end

  describe "patch/4" do
    test "replaces search string and returns updated artifact", ctx do
      FileSystem.write("page.html", "<h1>Old Title</h1><p>content</p>", opts(ctx))

      assert {:ok, %Artifact{} = artifact} =
               FileSystem.patch("page.html", "Old Title", "New Title", opts(ctx))

      assert artifact.filename == "page.html"
      assert File.read!(Path.join(dir(ctx), "page.html")) == "<h1>New Title</h1><p>content</p>"
    end

    test "replaces only the first occurrence", ctx do
      FileSystem.write("data.txt", "aaa", opts(ctx))

      assert {:ok, _} = FileSystem.patch("data.txt", "a", "b", opts(ctx))
      assert File.read!(Path.join(dir(ctx), "data.txt")) == "baa"
    end

    test "error when search string not found", ctx do
      FileSystem.write("file.txt", "hello world", opts(ctx))

      assert {:error, "search string not found in file.txt"} =
               FileSystem.patch("file.txt", "missing", "replacement", opts(ctx))
    end

    test "error on missing file", ctx do
      assert {:error, "artifact not found: nope.txt"} =
               FileSystem.patch("nope.txt", "a", "b", opts(ctx))
    end
  end

  describe "list/1" do
    test "returns artifacts sorted by filename", ctx do
      FileSystem.write("b.json", "{}", opts(ctx))
      FileSystem.write("a.html", "<h1>hi</h1>", opts(ctx))

      assert {:ok, [%Artifact{filename: "a.html"}, %Artifact{filename: "b.json"}]} =
               FileSystem.list(opts(ctx))
    end

    test "ignores dotfiles", ctx do
      FileSystem.write("visible.txt", "yes", opts(ctx))
      File.write!(Path.join(dir(ctx), ".hidden"), "no")

      assert {:ok, [%Artifact{filename: "visible.txt"}]} = FileSystem.list(opts(ctx))
    end

    test "ignores subdirectories", ctx do
      FileSystem.write("file.txt", "content", opts(ctx))
      File.mkdir_p!(Path.join(dir(ctx), "subdir"))

      assert {:ok, [%Artifact{filename: "file.txt"}]} = FileSystem.list(opts(ctx))
    end

    test "returns empty list for non-existent directory", ctx do
      assert {:ok, []} = FileSystem.list(session_id: "nonexistent", base_path: ctx.tmp_dir)
    end
  end

  describe "delete/2" do
    test "removes the file", ctx do
      FileSystem.write("temp.txt", "gone soon", opts(ctx))

      assert :ok = FileSystem.delete("temp.txt", opts(ctx))
      refute File.exists?(Path.join(dir(ctx), "temp.txt"))
    end

    test "error on missing file", ctx do
      assert {:error, "artifact not found: nope.txt"} = FileSystem.delete("nope.txt", opts(ctx))
    end
  end

  describe "filename validation" do
    test "rejects empty filename", ctx do
      assert {:error, "filename must not be empty"} = FileSystem.write("", "x", opts(ctx))
    end

    test "rejects path traversal", ctx do
      assert {:error, _} = FileSystem.write("../escape.txt", "x", opts(ctx))
      assert {:error, _} = FileSystem.read("../../etc/passwd", opts(ctx))
    end

    test "rejects forward slashes", ctx do
      assert {:error, "filename must not contain path separators"} =
               FileSystem.write("sub/file.txt", "x", opts(ctx))
    end

    test "rejects backslashes", ctx do
      assert {:error, "filename must not contain path separators"} =
               FileSystem.write("sub\\file.txt", "x", opts(ctx))
    end

    test "rejects null bytes", ctx do
      assert {:error, "filename must not contain null bytes"} =
               FileSystem.write("file\0.txt", "x", opts(ctx))
    end

    test "rejects dotfiles", ctx do
      assert {:error, "filename must not start with '.'"} =
               FileSystem.write(".secret", "x", opts(ctx))
    end
  end

  describe "base_path/1" do
    test "returns explicit opt when provided" do
      assert FileSystem.base_path(base_path: "/custom/path") == "/custom/path"
    end

    test "falls back to default containing omni/sessions" do
      assert FileSystem.base_path([]) =~ "omni/sessions"
    end
  end
end
