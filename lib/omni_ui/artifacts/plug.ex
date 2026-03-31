defmodule OmniUI.Artifacts.Plug do
  @moduledoc """
  Plug that serves artifact files over HTTP with signed token authorization.

  Mount in your router with `forward`:

      forward "/omni_artifacts", OmniUI.Artifacts.Plug

  Artifact URLs use signed tokens that encode the session ID, so only the
  LiveView that created the token can authorize access to a session's artifacts.
  Tokens are generated via `OmniUI.Artifacts.URL.artifact_url/3`.

  ## URL format

      GET /omni_artifacts/{token}/{filename}

  ## Options

    * `:max_age` — maximum token age in seconds (default: 86400 = 24 hours)
    * `:base_path` — override the artifacts base path (default: app config)
  """

  @behaviour Plug

  import Plug.Conn

  alias OmniUI.Artifacts.FileSystem
  alias OmniUI.Artifacts.URL

  @default_max_age 86_400

  @impl Plug
  def init(opts) do
    %{
      max_age: Keyword.get(opts, :max_age, @default_max_age),
      base_path: Keyword.get(opts, :base_path)
    }
  end

  @impl Plug
  def call(%Plug.Conn{path_info: [token, filename]} = conn, %{max_age: max_age} = opts) do
    endpoint = conn.private[:phoenix_endpoint]

    fs_opts = if opts[:base_path], do: [base_path: opts.base_path], else: []

    with {:ok, session_id} <- URL.verify_token(endpoint, token, max_age: max_age),
         dir = FileSystem.artifacts_dir([session_id: session_id] ++ fs_opts),
         path = Path.join(dir, filename),
         :ok <- verify_containment(path, dir),
         true <- File.regular?(path) do
      content_type = MIME.from_path(filename)

      conn
      |> put_resp_content_type(content_type, nil)
      |> put_resp_header("content-disposition", content_disposition(filename, content_type))
      |> put_resp_header("cache-control", "no-store")
      |> send_file(200, path)
    else
      {:error, _reason} -> send_resp(conn, 401, "Unauthorized")
      false -> send_resp(conn, 404, "Not Found")
    end
  end

  def call(conn, _opts) do
    send_resp(conn, 400, "Bad Request")
  end

  # Verifies the resolved path is inside the artifacts directory.
  # Prevents directory traversal via filenames like "../../etc/passwd".
  defp verify_containment(path, dir) do
    expanded = Path.expand(path)
    safe_dir = Path.expand(dir) <> "/"

    if String.starts_with?(expanded, safe_dir), do: :ok, else: false
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
