defmodule OmniUI.Artifacts.PlugTest.Endpoint do
  @moduledoc false
  def config(:secret_key_base), do: String.duplicate("a", 64)
end

defmodule OmniUI.Artifacts.PlugTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias Omni.Tools.Files.FS
  alias OmniUI.Artifacts.URL
  alias OmniUI.Artifacts.Plug, as: ArtifactPlug
  alias OmniUI.Artifacts.PlugTest.Endpoint

  @moduletag :tmp_dir
  @session_id "test-session"

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:omni_ui, :sessions_base_dir, tmp_dir)
    on_exit(fn -> Application.delete_env(:omni_ui, :sessions_base_dir) end)

    files_dir = OmniUI.Sessions.session_files_dir(@session_id)
    File.mkdir_p!(files_dir)
    fs = FS.new(base_dir: files_dir, nested: false)

    %{fs: fs}
  end

  defp sign(session_id), do: URL.sign_token(Endpoint, session_id)

  defp build_conn(token, filename) do
    Plug.Test.conn(:get, "/#{token}/#{filename}")
    |> put_private(:phoenix_endpoint, Endpoint)
  end

  defp call_plug(conn, plug_opts \\ []) do
    opts = ArtifactPlug.init(plug_opts)
    ArtifactPlug.call(conn, opts)
  end

  describe "successful serving" do
    test "serves HTML file with correct headers", %{fs: fs} do
      FS.write(fs, "page.html", "<h1>Hello</h1>")
      token = sign(@session_id)

      conn = build_conn(token, "page.html") |> call_plug()

      assert conn.status == 200
      assert conn.resp_body == "<h1>Hello</h1>"
      assert get_resp_header(conn, "content-type") == ["text/html"]
      assert get_resp_header(conn, "content-disposition") == ["inline"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "serves JSON file as inline", %{fs: fs} do
      FS.write(fs, "data.json", ~s({"key": "value"}))
      token = sign(@session_id)

      conn = build_conn(token, "data.json") |> call_plug()

      assert conn.status == 200
      assert conn.resp_body == ~s({"key": "value"})
      assert get_resp_header(conn, "content-type") == ["application/json"]
      assert get_resp_header(conn, "content-disposition") == ["inline"]
    end

    test "serves image file as inline", %{fs: fs} do
      FS.write(fs, "photo.png", "fake-png-data")
      token = sign(@session_id)

      conn = build_conn(token, "photo.png") |> call_plug()

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["image/png"]
      assert get_resp_header(conn, "content-disposition") == ["inline"]
    end

    test "serves binary file as attachment", %{fs: fs} do
      FS.write(fs, "report.xlsx", "fake-xlsx-data")
      token = sign(@session_id)

      conn = build_conn(token, "report.xlsx") |> call_plug()

      assert conn.status == 200

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="report.xlsx")
             ]
    end

    test "serves file whose name needs URI encoding", %{fs: fs} do
      FS.write(fs, "my app.html", "<p>spaced</p>")
      token = sign(@session_id)

      conn = build_conn(token, "my%20app.html") |> call_plug()

      assert conn.status == 200
      assert conn.resp_body == "<p>spaced</p>"
    end

    test "artifact_url encodes special characters in filename" do
      url = URL.artifact_url(Endpoint, "sess", "my app.html")
      assert url =~ "/my%20app.html"
      refute url =~ " "
    end
  end

  describe "missing file" do
    test "returns 404", %{fs: fs} do
      FS.write(fs, "exists.txt", "hi")
      token = sign(@session_id)

      conn = build_conn(token, "nope.txt") |> call_plug()

      assert conn.status == 404
    end
  end

  describe "authentication" do
    test "returns 401 for invalid token", %{fs: fs} do
      FS.write(fs, "page.html", "<h1>Hello</h1>")

      conn = build_conn("garbage-token", "page.html") |> call_plug()

      assert conn.status == 401
    end

    test "returns 401 for expired token", %{fs: fs} do
      FS.write(fs, "page.html", "<h1>Hello</h1>")
      token = Phoenix.Token.sign(Endpoint, "omni_ui:artifact", @session_id, signed_at: 0)

      conn = build_conn(token, "page.html") |> call_plug(max_age: 1)

      assert conn.status == 401
    end
  end

  describe "malformed paths" do
    test "returns 400 for no path segments" do
      conn =
        Plug.Test.conn(:get, "/")
        |> put_private(:phoenix_endpoint, Endpoint)
        |> call_plug()

      assert conn.status == 400
    end

    test "returns 400 for single path segment" do
      conn =
        Plug.Test.conn(:get, "/only-a-token")
        |> put_private(:phoenix_endpoint, Endpoint)
        |> call_plug()

      assert conn.status == 400
    end

    test "returns 400 for three path segments" do
      conn =
        Plug.Test.conn(:get, "/a/b/c")
        |> put_private(:phoenix_endpoint, Endpoint)
        |> call_plug()

      assert conn.status == 400
    end
  end

  describe "path traversal" do
    test "returns 404 for traversal attempt", %{fs: fs} do
      FS.write(fs, "safe.txt", "content")
      token = sign(@session_id)

      conn =
        Plug.Test.conn(:get, "/")
        |> put_private(:phoenix_endpoint, Endpoint)
        |> Map.put(:path_info, [token, "../../etc/passwd"])
        |> call_plug()

      assert conn.status == 404
    end
  end
end
