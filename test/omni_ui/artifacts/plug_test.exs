defmodule OmniUI.Artifacts.PlugTest.Endpoint do
  @moduledoc false
  def config(:secret_key_base), do: String.duplicate("a", 64)
end

defmodule OmniUI.Artifacts.PlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias OmniUI.Artifacts.{FileSystem, URL}
  alias OmniUI.Artifacts.Plug, as: ArtifactPlug
  alias OmniUI.Artifacts.PlugTest.Endpoint

  @moduletag :tmp_dir

  defp opts(%{tmp_dir: tmp_dir}), do: [session_id: "test-session", base_path: tmp_dir]

  defp sign(session_id), do: URL.sign_token(Endpoint, session_id)

  defp build_conn(token, filename) do
    Plug.Test.conn(:get, "/#{token}/#{filename}")
    |> put_private(:phoenix_endpoint, Endpoint)
  end

  defp call_plug(conn, plug_opts \\ [], ctx \\ %{})

  defp call_plug(conn, plug_opts, %{tmp_dir: tmp_dir}) do
    opts = ArtifactPlug.init([base_path: tmp_dir] ++ plug_opts)
    ArtifactPlug.call(conn, opts)
  end

  defp call_plug(conn, plug_opts, _ctx) do
    opts = ArtifactPlug.init(plug_opts)
    ArtifactPlug.call(conn, opts)
  end

  describe "successful serving" do
    test "serves HTML file with correct headers", ctx do
      FileSystem.write("page.html", "<h1>Hello</h1>", opts(ctx))
      token = sign("test-session")

      conn = build_conn(token, "page.html") |> call_plug([], ctx)

      assert conn.status == 200
      assert conn.resp_body == "<h1>Hello</h1>"
      assert get_resp_header(conn, "content-type") == ["text/html"]
      assert get_resp_header(conn, "content-disposition") == ["inline"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "serves JSON file as inline", ctx do
      FileSystem.write("data.json", ~s({"key": "value"}), opts(ctx))
      token = sign("test-session")

      conn = build_conn(token, "data.json") |> call_plug([], ctx)

      assert conn.status == 200
      assert conn.resp_body == ~s({"key": "value"})
      assert get_resp_header(conn, "content-type") == ["application/json"]
      assert get_resp_header(conn, "content-disposition") == ["inline"]
    end

    test "serves image file as inline", ctx do
      FileSystem.write("photo.png", "fake-png-data", opts(ctx))
      token = sign("test-session")

      conn = build_conn(token, "photo.png") |> call_plug([], ctx)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["image/png"]
      assert get_resp_header(conn, "content-disposition") == ["inline"]
    end

    test "serves binary file as attachment", ctx do
      FileSystem.write("report.xlsx", "fake-xlsx-data", opts(ctx))
      token = sign("test-session")

      conn = build_conn(token, "report.xlsx") |> call_plug([], ctx)

      assert conn.status == 200

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="report.xlsx")
             ]
    end

    test "serves file whose name needs URI encoding", ctx do
      FileSystem.write("my app.html", "<p>spaced</p>", opts(ctx))
      token = sign("test-session")

      # path_info preserves percent-encoding; the Plug must decode it
      conn = build_conn(token, "my%20app.html") |> call_plug([], ctx)

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
    test "returns 404", ctx do
      FileSystem.write("exists.txt", "hi", opts(ctx))
      token = sign("test-session")

      conn = build_conn(token, "nope.txt") |> call_plug([], ctx)

      assert conn.status == 404
    end
  end

  describe "authentication" do
    test "returns 401 for invalid token", ctx do
      FileSystem.write("page.html", "<h1>Hello</h1>", opts(ctx))

      conn = build_conn("garbage-token", "page.html") |> call_plug([], ctx)

      assert conn.status == 401
    end

    test "returns 401 for expired token", ctx do
      FileSystem.write("page.html", "<h1>Hello</h1>", opts(ctx))
      token = Phoenix.Token.sign(Endpoint, "omni_ui:artifact", "test-session", signed_at: 0)

      conn = build_conn(token, "page.html") |> call_plug([max_age: 1], ctx)

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
    test "returns 404 for traversal attempt", ctx do
      FileSystem.write("safe.txt", "content", opts(ctx))
      token = sign("test-session")

      # Simulate a decoded traversal filename as a real server would deliver
      # (Plug.Test.conn splits on "/" so we set path_info directly)
      conn =
        Plug.Test.conn(:get, "/")
        |> put_private(:phoenix_endpoint, Endpoint)
        |> Map.put(:path_info, [token, "../../etc/passwd"])
        |> call_plug([], ctx)

      assert conn.status == 404
    end
  end
end
