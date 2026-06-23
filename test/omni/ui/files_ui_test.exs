defmodule Omni.UI.FilesUITest do
  use Omni.UI.ComponentCase, async: true

  import Omni.UI.FilesUI
  alias Omni.Tools.Files.Entry

  defp sample_entry(overrides \\ %{}) do
    Map.merge(
      %Entry{
        id: "notes/todo.md",
        filename: "todo.md",
        media_type: "text/markdown",
        size: 2048,
        mtime: ~U[2026-03-15 10:30:00Z]
      },
      overrides
    )
  end

  # ── files_panel_header/1 ─────────────────────────────────────────

  describe "files_panel_header/1" do
    test "renders title and list icon when no file selected" do
      assigns = %{token: "tok123"}

      html =
        rendered_to_string(~H"""
        <.files_panel_header token={@token} />
        """)

      assert html =~ "All files"
    end

    test "renders back arrow when file is selected" do
      assigns = %{file: sample_entry(), token: "tok123"}

      html =
        rendered_to_string(~H"""
        <.files_panel_header file={@file} token={@token} />
        """)

      assert html =~ ~s(phx-click="close")
    end

    test "renders download link when file is selected" do
      assigns = %{file: sample_entry(), token: "tok123"}

      html =
        rendered_to_string(~H"""
        <.files_panel_header file={@file} token={@token} />
        """)

      assert html =~ ~s(download="todo.md")
      assert html =~ "tok123"
    end

    test "renders close button" do
      assigns = %{token: "tok123"}

      html =
        rendered_to_string(~H"""
        <.files_panel_header token={@token} />
        """)

      assert html =~ "Close files"
    end

    test "shows source toggle for html files" do
      assigns = %{file: sample_entry(%{media_type: "text/html"}), token: "tok"}

      html =
        rendered_to_string(~H"""
        <.files_panel_header file={@file} token={@token} />
        """)

      assert html =~ "Preview"
      assert html =~ "Code"
    end

    test "shows source toggle for markdown files" do
      assigns = %{file: sample_entry(%{media_type: "text/markdown"}), token: "tok"}

      html =
        rendered_to_string(~H"""
        <.files_panel_header file={@file} token={@token} />
        """)

      assert html =~ "Preview"
    end

    test "hides source toggle for plain text files" do
      assigns = %{file: sample_entry(%{media_type: "text/plain"}), token: "tok"}

      html =
        rendered_to_string(~H"""
        <.files_panel_header file={@file} token={@token} />
        """)

      refute html =~ "Preview"
    end
  end

  # ── file_list/1 ──────────────────────────────────────────────────

  describe "file_list/1" do
    test "renders empty state" do
      assigns = %{files: %{}}

      html =
        rendered_to_string(~H"""
        <.file_list files={@files} />
        """)

      assert html =~ "No files yet."
    end

    test "renders file entries with name, size, and date" do
      files = %{
        "readme.md" => sample_entry(%{filename: "readme.md", size: 512}),
        "app.js" => sample_entry(%{filename: "app.js", size: 3072})
      }

      assigns = %{files: files}

      html =
        rendered_to_string(~H"""
        <.file_list files={@files} />
        """)

      assert html =~ "readme.md"
      assert html =~ "app.js"
      assert html =~ "512 B"
      assert html =~ "3.0 KB"
    end

    test "renders column headers" do
      assigns = %{files: %{"a.txt" => sample_entry()}}

      html =
        rendered_to_string(~H"""
        <.file_list files={@files} />
        """)

      assert html =~ "Name"
      assert html =~ "Size"
      assert html =~ "Updated"
    end

    test "file rows are clickable with open event" do
      assigns = %{files: %{"a.txt" => sample_entry(%{filename: "a.txt"})}}

      html =
        rendered_to_string(~H"""
        <.file_list files={@files} />
        """)

      assert html =~ ~s(phx-click="open")
      assert html =~ ~s(phx-value-filename="a.txt")
    end

    test "renders error message" do
      assigns = %{files: %{}, error: "Permission denied"}

      html =
        rendered_to_string(~H"""
        <.file_list files={@files} error={@error} />
        """)

      assert html =~ "Permission denied"
    end
  end

  # ── file_view/1 ──────────────────────────────────────────────────

  describe "file_view/1" do
    test "iframe view renders iframe with file url" do
      assigns = %{
        file: sample_entry(%{media_type: "application/pdf"}),
        view: :iframe,
        token: "tok"
      }

      html =
        rendered_to_string(~H"""
        <.file_view file={@file} view={@view} token={@token} />
        """)

      assert html =~ "<iframe"
      assert html =~ "tok"
    end

    test "iframe view adds sandbox allow-scripts for html" do
      assigns = %{
        file: sample_entry(%{media_type: "text/html"}),
        view: :iframe,
        token: "tok"
      }

      html =
        rendered_to_string(~H"""
        <.file_view file={@file} view={@view} token={@token} />
        """)

      assert html =~ "allow-scripts"
    end

    test "iframe view omits sandbox for non-html" do
      assigns = %{
        file: sample_entry(%{media_type: "application/pdf"}),
        view: :iframe,
        token: "tok"
      }

      html =
        rendered_to_string(~H"""
        <.file_view file={@file} view={@view} token={@token} />
        """)

      refute html =~ "allow-scripts"
    end

    test "markdown view renders content in prose container" do
      assigns = %{
        file: sample_entry(),
        view: :markdown,
        content: Phoenix.HTML.raw("<p>Hello</p>"),
        token: "tok"
      }

      html =
        rendered_to_string(~H"""
        <.file_view file={@file} view={@view} content={@content} token={@token} />
        """)

      assert html =~ "mdex"
      assert html =~ "<p>Hello</p>"
    end

    test "source view renders content in code container" do
      assigns = %{
        file: sample_entry(),
        view: :source,
        content: Phoenix.HTML.raw("<pre>code here</pre>"),
        token: "tok"
      }

      html =
        rendered_to_string(~H"""
        <.file_view file={@file} view={@view} content={@content} token={@token} />
        """)

      assert html =~ "code here"
      assert html =~ "whitespace-pre-wrap"
    end

    test "media view renders image with alt text" do
      assigns = %{
        file: sample_entry(%{filename: "photo.png", media_type: "image/png"}),
        view: :media,
        token: "tok"
      }

      html =
        rendered_to_string(~H"""
        <.file_view file={@file} view={@view} token={@token} />
        """)

      assert html =~ "<img"
      assert html =~ ~s(alt="photo.png")
    end

    test "download view renders download link" do
      assigns = %{
        file: sample_entry(%{filename: "data.zip"}),
        view: :download,
        token: "tok"
      }

      html =
        rendered_to_string(~H"""
        <.file_view file={@file} view={@view} token={@token} />
        """)

      assert html =~ ~s(download="data.zip")
      assert html =~ "Download"
    end
  end

  # ── source_toggle/1 ─────────────────────────────────────────────

  describe "source_toggle/1" do
    test "highlights Preview when view_source is false" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.source_toggle view_source={false} />
        """)

      assert html =~ ~r/shadow-sm[^"]*">\s*Preview/s
    end

    test "highlights Code when view_source is true" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.source_toggle view_source={true} />
        """)

      assert html =~ ~r/shadow-sm[^"]*">\s*Code/s
    end
  end
end
