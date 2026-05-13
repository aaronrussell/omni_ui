defmodule OmniUI.Artifacts.Plug do
  @moduledoc """
  Plug that serves artifact files over HTTP with signed token authorization.

  Mount in your router with `forward`:

      forward "/omni_files", OmniUI.Artifacts.Plug

  Artifact URLs use signed tokens that encode the session ID, so only the
  LiveView that created the token can authorize access to a session's artifacts.
  Tokens are generated via `OmniUI.Artifacts.URL.artifact_url/3`.

  ## URL format

      GET /omni_files/{token}/{filename}

  ## Options

    * `:max_age` — maximum token age in seconds (default: 86400 = 24 hours)
  """

  @behaviour Plug

  import Plug.Conn

  alias Omni.Tools.Files.FS
  alias OmniUI.Artifacts.URL

  @default_max_age 86_400

  @impl Plug
  def init(opts) do
    %{
      max_age: Keyword.get(opts, :max_age, @default_max_age)
    }
  end

  @impl Plug
  def call(%Plug.Conn{path_info: [token, raw_filename]} = conn, %{max_age: max_age}) do
    endpoint = conn.private[:phoenix_endpoint]
    filename = URI.decode(raw_filename)

    with {:ok, session_id} <- URL.verify_token(endpoint, token, max_age: max_age),
         fs = FS.new(base_dir: OmniUI.Sessions.session_files_dir(session_id), nested: false),
         {:ok, path} <- FS.resolve(fs, filename),
         true <- File.regular?(path) do
      content_type = MIME.from_path(filename)

      conn
      |> put_cors_headers()
      |> put_resp_content_type(content_type, nil)
      |> put_resp_header("content-disposition", content_disposition(filename, content_type))
      |> put_resp_header("cache-control", "no-store")
      |> send_file(200, path)
    else
      {:error, reason} when reason in [:invalid, :expired] ->
        send_resp(conn, 401, "Unauthorized")

      {:error, _reason} ->
        send_resp(conn, 404, "Not Found")

      false ->
        send_resp(conn, 404, "Not Found")
    end
  end

  # CORS preflight for sandboxed iframes (origin: null)
  def call(%Plug.Conn{method: "OPTIONS", path_info: [_token, _filename]} = conn, _opts) do
    conn
    |> put_cors_headers()
    |> send_resp(204, "")
  end

  def call(conn, _opts) do
    send_resp(conn, 400, "Bad Request")
  end

  # Sandboxed iframes have origin "null", so artifact sub-resources (fetch, img,
  # etc.) need CORS headers. Access is already gated by the signed URL token.
  defp put_cors_headers(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type")
  end

  defp content_disposition(filename, content_type) do
    if inline?(content_type) do
      "inline"
    else
      ~s(attachment; filename="#{filename}")
    end
  end

  defp inline?(type) do
    String.starts_with?(type, "text/") or
      String.starts_with?(type, "image/") or
      type in ["application/json", "application/pdf"]
  end
end
