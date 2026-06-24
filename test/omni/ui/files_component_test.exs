defmodule Omni.UI.FilesComponentTest.Endpoint do
  @moduledoc false
  def config(:secret_key_base), do: String.duplicate("a", 64)
end

defmodule Omni.UI.FilesComponentTest do
  use Omni.UI.ComponentCase, async: false

  alias Omni.Tools.Files.FS
  alias Omni.UI.FilesComponent
  alias Omni.UI.FilesComponentTest.Endpoint

  @endpoint Endpoint
  @session_id "test-session-fc"

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    prev = Application.get_env(:omni_ui, Omni.UI.Sessions)

    Application.put_env(
      :omni_ui,
      Omni.UI.Sessions,
      Keyword.put(prev || [], :sessions_base_dir, tmp_dir)
    )

    on_exit(fn ->
      if prev,
        do: Application.put_env(:omni_ui, Omni.UI.Sessions, prev),
        else: Application.delete_env(:omni_ui, Omni.UI.Sessions)
    end)

    files_dir = Omni.UI.Sessions.session_files_dir(@session_id)
    File.mkdir_p!(files_dir)
    fs = FS.new(base_dir: files_dir, nested: false)

    %{fs: fs, files_dir: files_dir}
  end

  defp build_socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      endpoint: Endpoint,
      assigns: Map.merge(%{__changed__: %{}}, assigns),
      private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}}
    }
  end

  defp mount_component do
    {:ok, socket} = FilesComponent.mount(build_socket())
    socket
  end

  defp apply_update(socket, assigns) do
    {:ok, socket} = FilesComponent.update(assigns, socket)
    socket
  end

  defp safe_to_string({:safe, html}), do: html
  defp safe_to_string(str) when is_binary(str), do: str

  # ── mount ───────────────────────────────────────────────────────

  describe "mount/1" do
    test "initialises with empty state" do
      socket = mount_component()

      assert socket.assigns.files == %{}
      assert socket.assigns.active_file == nil
      assert socket.assigns.content == nil
      assert socket.assigns.error == nil
      assert socket.assigns.view == nil
      assert socket.assigns.view_source == false
      assert socket.assigns.session_id == nil
      assert socket.assigns.token == nil
    end
  end

  # ── update: session_id changes ──────────────────────────────────

  describe "update/2 with session_id" do
    test "scans files when session_id is set", %{fs: fs} do
      FS.write(fs, "hello.txt", "world")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      assert Map.has_key?(socket.assigns.files, "hello.txt")
      assert socket.assigns.token != nil
    end

    test "is a no-op when session_id is unchanged", %{fs: fs} do
      FS.write(fs, "hello.txt", "world")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      original_token = socket.assigns.token

      socket = apply_update(socket, %{session_id: @session_id})

      assert socket.assigns.token == original_token
    end

    test "resets state when session_id becomes nil", %{fs: fs} do
      FS.write(fs, "hello.txt", "world")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})
        |> apply_update(%{session_id: nil})

      assert socket.assigns.files == %{}
      assert socket.assigns.active_file == nil
      assert socket.assigns.content == nil
      assert socket.assigns.view == nil
      assert socket.assigns.view_source == false
      assert socket.assigns.token == nil
    end

    test "rescans when session_id changes to a different value", %{tmp_dir: tmp_dir} do
      other_id = "other-session"
      other_dir = Path.join([tmp_dir, other_id, "files"])
      File.mkdir_p!(other_dir)
      other_fs = FS.new(base_dir: other_dir, nested: false)
      FS.write(other_fs, "other.md", "# Other")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})
        |> apply_update(%{session_id: other_id})

      assert Map.has_key?(socket.assigns.files, "other.md")
      refute Map.has_key?(socket.assigns.files, "hello.txt")
    end
  end

  # ── update: :rescan action ──────────────────────────────────────

  describe "update/2 with action: :rescan" do
    test "refreshes the file list", %{fs: fs} do
      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      assert socket.assigns.files == %{}

      FS.write(fs, "new.txt", "appeared")
      socket = apply_update(socket, %{action: :rescan})

      assert Map.has_key?(socket.assigns.files, "new.txt")
    end

    test "clears active_file when the file was deleted", %{fs: fs} do
      FS.write(fs, "temp.txt", "will be deleted")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      {:noreply, socket} =
        FilesComponent.handle_event("open", %{"filename" => "temp.txt"}, socket)

      assert socket.assigns.active_file == "temp.txt"

      File.rm!(Path.join(Omni.UI.Sessions.session_files_dir(@session_id), "temp.txt"))
      socket = apply_update(socket, %{action: :rescan})

      assert socket.assigns.active_file == nil
    end

    test "refreshes content when active file still exists", %{fs: fs} do
      FS.write(fs, "data.txt", "original")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      {:noreply, socket} =
        FilesComponent.handle_event("open", %{"filename" => "data.txt"}, socket)

      assert safe_to_string(socket.assigns.content) =~ "original"

      FS.write(fs, "data.txt", "updated")
      socket = apply_update(socket, %{action: :rescan})

      assert safe_to_string(socket.assigns.content) =~ "updated"
    end
  end

  # ── update: {:view, filename} action ────────────────────────────

  describe "update/2 with action: {:view, filename}" do
    test "opens the named file", %{fs: fs} do
      FS.write(fs, "report.txt", "contents")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})
        |> apply_update(%{action: {:view, "report.txt"}})

      assert socket.assigns.active_file == "report.txt"
      assert safe_to_string(socket.assigns.content) =~ "contents"
    end

    test "sets error when file does not exist", %{fs: fs} do
      FS.write(fs, "exists.txt", "here")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})
        |> apply_update(%{action: {:view, "gone.txt"}})

      assert socket.assigns.active_file == nil
      assert socket.assigns.error =~ "gone.txt"
      assert socket.assigns.error =~ "deleted"
    end

    test "resets view_source when opening via action", %{fs: fs} do
      FS.write(fs, "page.html", "<h1>Hi</h1>")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      {:noreply, socket} =
        FilesComponent.handle_event("open", %{"filename" => "page.html"}, socket)

      {:noreply, socket} = FilesComponent.handle_event("toggle", %{}, socket)
      assert socket.assigns.view_source == true

      socket = apply_update(socket, %{action: {:view, "page.html"}})
      assert socket.assigns.view_source == false
    end
  end

  # ── handle_event: open ──────────────────────────────────────────

  describe "handle_event open" do
    test "selects a file and loads its content", %{fs: fs} do
      FS.write(fs, "readme.txt", "Read me")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      {:noreply, socket} =
        FilesComponent.handle_event("open", %{"filename" => "readme.txt"}, socket)

      assert socket.assigns.active_file == "readme.txt"
      assert safe_to_string(socket.assigns.content) =~ "Read me"
      assert socket.assigns.view == :source
    end

    test "resets view_source to false", %{fs: fs} do
      FS.write(fs, "code.js", "console.log('hi')")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      {:noreply, socket} =
        FilesComponent.handle_event("open", %{"filename" => "code.js"}, socket)

      {:noreply, socket} = FilesComponent.handle_event("toggle", %{}, socket)
      assert socket.assigns.view_source == true

      {:noreply, socket} =
        FilesComponent.handle_event("open", %{"filename" => "code.js"}, socket)

      assert socket.assigns.view_source == false
    end
  end

  # ── handle_event: toggle ────────────────────────────────────────

  describe "handle_event toggle" do
    test "flips view_source and reloads content", %{fs: fs} do
      FS.write(fs, "page.html", "<p>Hello</p>")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      {:noreply, socket} =
        FilesComponent.handle_event("open", %{"filename" => "page.html"}, socket)

      assert socket.assigns.view == :iframe
      assert socket.assigns.view_source == false

      {:noreply, socket} = FilesComponent.handle_event("toggle", %{}, socket)

      assert socket.assigns.view_source == true
      assert socket.assigns.view == :source
      assert safe_to_string(socket.assigns.content) =~ "Hello"
    end

    test "toggles back to default view", %{fs: fs} do
      FS.write(fs, "notes.md", "# Notes")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      {:noreply, socket} =
        FilesComponent.handle_event("open", %{"filename" => "notes.md"}, socket)

      assert socket.assigns.view == :markdown

      {:noreply, socket} = FilesComponent.handle_event("toggle", %{}, socket)
      assert socket.assigns.view == :source

      {:noreply, socket} = FilesComponent.handle_event("toggle", %{}, socket)
      assert socket.assigns.view == :markdown
    end
  end

  # ── handle_event: close ─────────────────────────────────────────

  describe "handle_event close" do
    test "clears file selection state", %{fs: fs} do
      FS.write(fs, "file.txt", "data")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      {:noreply, socket} =
        FilesComponent.handle_event("open", %{"filename" => "file.txt"}, socket)

      assert socket.assigns.active_file == "file.txt"

      {:noreply, socket} = FilesComponent.handle_event("close", %{}, socket)

      assert socket.assigns.active_file == nil
      assert socket.assigns.content == nil
      assert socket.assigns.view == nil
      assert socket.assigns.view_source == false
    end
  end

  # ── view mode determination ─────────────────────────────────────

  describe "view mode" do
    test "HTML files open as iframe", %{fs: fs} do
      FS.write(fs, "page.html", "<h1>Hi</h1>")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      {:noreply, socket} =
        FilesComponent.handle_event("open", %{"filename" => "page.html"}, socket)

      assert socket.assigns.view == :iframe
      assert socket.assigns.content == nil
    end

    test "markdown files open as markdown", %{fs: fs} do
      FS.write(fs, "readme.md", "# Title")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      {:noreply, socket} =
        FilesComponent.handle_event("open", %{"filename" => "readme.md"}, socket)

      assert socket.assigns.view == :markdown
      assert socket.assigns.content != nil
    end

    test "images open as media", %{fs: fs} do
      FS.write(fs, "photo.png", "fake-png")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      {:noreply, socket} =
        FilesComponent.handle_event("open", %{"filename" => "photo.png"}, socket)

      assert socket.assigns.view == :media
      assert socket.assigns.content == nil
    end

    test "JSON files open as source", %{fs: fs} do
      FS.write(fs, "data.json", ~s({"key": "val"}))

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      {:noreply, socket} =
        FilesComponent.handle_event("open", %{"filename" => "data.json"}, socket)

      assert socket.assigns.view == :source
      assert safe_to_string(socket.assigns.content) =~ "key"
    end

    test "plain text files open as source", %{fs: fs} do
      FS.write(fs, "notes.txt", "some notes")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      {:noreply, socket} =
        FilesComponent.handle_event("open", %{"filename" => "notes.txt"}, socket)

      assert socket.assigns.view == :source
      assert safe_to_string(socket.assigns.content) =~ "some notes"
    end

    test "PDF files open as iframe", %{fs: fs} do
      FS.write(fs, "doc.pdf", "fake-pdf")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      {:noreply, socket} =
        FilesComponent.handle_event("open", %{"filename" => "doc.pdf"}, socket)

      assert socket.assigns.view == :iframe
    end

    test "unknown binary types open as download", %{fs: fs} do
      FS.write(fs, "archive.zip", "fake-zip")

      socket =
        mount_component()
        |> apply_update(%{session_id: @session_id})

      {:noreply, socket} =
        FilesComponent.handle_event("open", %{"filename" => "archive.zip"}, socket)

      assert socket.assigns.view == :download
      assert socket.assigns.content == nil
    end
  end

  # ── render ──────────────────────────────────────────────────────

  describe "render" do
    test "renders file list when no file is selected", %{fs: fs} do
      FS.write(fs, "alpha.txt", "a")
      FS.write(fs, "beta.md", "b")

      html =
        render_component(FilesComponent,
          id: "files",
          session_id: @session_id
        )

      assert html =~ "alpha.txt"
      assert html =~ "beta.md"
    end

    test "renders empty state when no files exist" do
      html =
        render_component(FilesComponent,
          id: "files",
          session_id: @session_id
        )

      assert html =~ "No files"
    end

    test "renders empty state without session_id" do
      html =
        render_component(FilesComponent,
          id: "files",
          session_id: nil
        )

      assert html =~ "No files"
    end
  end
end
