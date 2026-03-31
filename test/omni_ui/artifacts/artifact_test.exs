defmodule OmniUI.Artifacts.ArtifactTest do
  use ExUnit.Case, async: true

  alias OmniUI.Artifacts.Artifact

  describe "new/1" do
    test "builds struct from keyword list" do
      now = DateTime.utc_now()

      artifact =
        Artifact.new(
          filename: "report.html",
          mime_type: "text/html",
          size: 1024,
          updated_at: now
        )

      assert %Artifact{
               filename: "report.html",
               mime_type: "text/html",
               size: 1024,
               updated_at: ^now
             } = artifact
    end

    test "auto-derives mime_type from filename" do
      artifact = Artifact.new(filename: "data.json", size: 42)

      assert artifact.mime_type == "application/json"
    end

    test "does not override explicit mime_type" do
      artifact = Artifact.new(filename: "data.json", size: 42, mime_type: "text/plain")

      assert artifact.mime_type == "text/plain"
    end

    test "auto-sets updated_at when not provided" do
      before = DateTime.utc_now()
      artifact = Artifact.new(filename: "test.txt", size: 0)
      after_ = DateTime.utc_now()

      assert DateTime.compare(artifact.updated_at, before) in [:eq, :gt]
      assert DateTime.compare(artifact.updated_at, after_) in [:eq, :lt]
    end

    test "does not override explicit updated_at" do
      ts = ~U[2025-01-01 00:00:00Z]
      artifact = Artifact.new(filename: "test.txt", size: 0, updated_at: ts)

      assert artifact.updated_at == ts
    end
  end

  describe "new/2" do
    test "builds struct from filename and File.Stat" do
      stat = %File.Stat{size: 2048, mtime: 1_700_000_000}
      artifact = Artifact.new("dashboard.html", stat)

      assert artifact.filename == "dashboard.html"
      assert artifact.mime_type == "text/html"
      assert artifact.size == 2048
      assert artifact.updated_at == DateTime.from_unix!(1_700_000_000)
    end

    test "derives MIME type from extension" do
      stat = %File.Stat{size: 0, mtime: 0}

      assert Artifact.new("data.json", stat).mime_type == "application/json"
      assert Artifact.new("style.css", stat).mime_type == "text/css"
      assert Artifact.new("image.png", stat).mime_type == "image/png"

      assert Artifact.new("report.xlsx", stat).mime_type ==
               "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    end

    test "falls back to application/octet-stream for unknown extensions" do
      stat = %File.Stat{size: 0, mtime: 0}

      assert Artifact.new("Makefile", stat).mime_type == "application/octet-stream"
      assert Artifact.new("data.xyz", stat).mime_type == "application/octet-stream"
    end
  end
end
