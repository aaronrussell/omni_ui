defmodule OmniUI.Artifacts.FileSystemTest do
  use ExUnit.Case, async: true

  alias OmniUI.Artifacts.{Artifact, FileSystem}

  @moduletag :tmp_dir

  defp dir(%{tmp_dir: tmp_dir}), do: Path.join(tmp_dir, "artifacts")

  describe "write/3" do
    test "creates file and returns artifact", ctx do
      dir = dir(ctx)

      assert {:ok, %Artifact{} = artifact} = FileSystem.write(dir, "report.html", "<h1>Hi</h1>")

      assert artifact.filename == "report.html"
      assert artifact.mime_type == "text/html"
      assert artifact.size == byte_size("<h1>Hi</h1>")
      assert %DateTime{} = artifact.updated_at
      assert File.read!(Path.join(dir, "report.html")) == "<h1>Hi</h1>"
    end

    test "creates directory if it doesn't exist", ctx do
      dir = Path.join(dir(ctx), "nested")
      refute File.dir?(dir)

      assert {:ok, _} = FileSystem.write(dir, "test.txt", "hello")
      assert File.dir?(dir)
    end

    test "upserts — overwrites existing file", ctx do
      dir = dir(ctx)

      assert {:ok, _} = FileSystem.write(dir, "data.json", ~s({"v":1}))
      assert {:ok, artifact} = FileSystem.write(dir, "data.json", ~s({"v":2}))

      assert artifact.size == byte_size(~s({"v":2}))
      assert File.read!(Path.join(dir, "data.json")) == ~s({"v":2})
    end
  end

  describe "read/2" do
    test "returns file content", ctx do
      dir = dir(ctx)
      FileSystem.write(dir, "hello.txt", "world")

      assert {:ok, "world"} = FileSystem.read(dir, "hello.txt")
    end

    test "error on missing file", ctx do
      assert {:error, "artifact not found: nope.txt"} = FileSystem.read(dir(ctx), "nope.txt")
    end
  end

  describe "patch/4" do
    test "replaces search string and returns updated artifact", ctx do
      dir = dir(ctx)
      FileSystem.write(dir, "page.html", "<h1>Old Title</h1><p>content</p>")

      assert {:ok, %Artifact{} = artifact} =
               FileSystem.patch(dir, "page.html", "Old Title", "New Title")

      assert artifact.filename == "page.html"
      assert File.read!(Path.join(dir, "page.html")) == "<h1>New Title</h1><p>content</p>"
    end

    test "replaces only the first occurrence", ctx do
      dir = dir(ctx)
      FileSystem.write(dir, "data.txt", "aaa")

      assert {:ok, _} = FileSystem.patch(dir, "data.txt", "a", "b")
      assert File.read!(Path.join(dir, "data.txt")) == "baa"
    end

    test "error when search string not found", ctx do
      dir = dir(ctx)
      FileSystem.write(dir, "file.txt", "hello world")

      assert {:error, "search string not found in file.txt"} =
               FileSystem.patch(dir, "file.txt", "missing", "replacement")
    end

    test "error on missing file", ctx do
      assert {:error, "artifact not found: nope.txt"} =
               FileSystem.patch(dir(ctx), "nope.txt", "a", "b")
    end
  end

  describe "list/1" do
    test "returns artifacts sorted by filename", ctx do
      dir = dir(ctx)
      FileSystem.write(dir, "b.json", "{}")
      FileSystem.write(dir, "a.html", "<h1>hi</h1>")

      assert {:ok, [%Artifact{filename: "a.html"}, %Artifact{filename: "b.json"}]} =
               FileSystem.list(dir)
    end

    test "ignores dotfiles", ctx do
      dir = dir(ctx)
      FileSystem.write(dir, "visible.txt", "yes")
      File.write!(Path.join(dir, ".hidden"), "no")

      assert {:ok, [%Artifact{filename: "visible.txt"}]} = FileSystem.list(dir)
    end

    test "ignores subdirectories", ctx do
      dir = dir(ctx)
      FileSystem.write(dir, "file.txt", "content")
      File.mkdir_p!(Path.join(dir, "subdir"))

      assert {:ok, [%Artifact{filename: "file.txt"}]} = FileSystem.list(dir)
    end

    test "returns empty list for non-existent directory", ctx do
      assert {:ok, []} = FileSystem.list(Path.join(ctx.tmp_dir, "nope"))
    end
  end

  describe "delete/2" do
    test "removes the file", ctx do
      dir = dir(ctx)
      FileSystem.write(dir, "temp.txt", "gone soon")

      assert :ok = FileSystem.delete(dir, "temp.txt")
      refute File.exists?(Path.join(dir, "temp.txt"))
    end

    test "error on missing file", ctx do
      assert {:error, "artifact not found: nope.txt"} = FileSystem.delete(dir(ctx), "nope.txt")
    end
  end

  describe "filename validation" do
    test "rejects empty filename", ctx do
      assert {:error, "filename must not be empty"} = FileSystem.write(dir(ctx), "", "x")
    end

    test "rejects path traversal", ctx do
      assert {:error, _} = FileSystem.write(dir(ctx), "../escape.txt", "x")
      assert {:error, _} = FileSystem.read(dir(ctx), "../../etc/passwd")
    end

    test "rejects forward slashes", ctx do
      assert {:error, "filename must not contain path separators"} =
               FileSystem.write(dir(ctx), "sub/file.txt", "x")
    end

    test "rejects backslashes", ctx do
      assert {:error, "filename must not contain path separators"} =
               FileSystem.write(dir(ctx), "sub\\file.txt", "x")
    end

    test "rejects null bytes", ctx do
      assert {:error, "filename must not contain null bytes"} =
               FileSystem.write(dir(ctx), "file\0.txt", "x")
    end

    test "rejects dotfiles", ctx do
      assert {:error, "filename must not start with '.'"} =
               FileSystem.write(dir(ctx), ".secret", "x")
    end
  end
end
