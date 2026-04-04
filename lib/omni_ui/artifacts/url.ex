defmodule OmniUI.Artifacts.URL do
  @moduledoc """
  Token signing, verification, and URL construction for artifact serving.

  Uses `Phoenix.Token` to create signed tokens that encode a session ID,
  allowing the `OmniUI.Artifacts.Plug` to authorize access without shared state.

  ## Configuration

      config :omni_ui, OmniUI.Artifacts, url_prefix: "/omni_artifacts"

  The `:url_prefix` defaults to `"/omni_artifacts"` and should match the path
  where `OmniUI.Artifacts.Plug` is mounted in the router.
  """

  @salt "omni_ui:artifact"

  @doc """
  Signs a session ID into a token for use in artifact URLs.

  The `endpoint` argument accepts an endpoint module, a `Plug.Conn`, or a
  `Phoenix.LiveView.Socket` — any context valid for `Phoenix.Token.sign/4`.

  ## Examples

      token = URL.sign_token(socket.endpoint, session_id)
      token = URL.sign_token(conn, session_id)
  """
  @spec sign_token(atom() | Plug.Conn.t() | Phoenix.LiveView.Socket.t(), String.t()) ::
          String.t()
  def sign_token(endpoint, session_id) do
    Phoenix.Token.sign(endpoint, @salt, session_id)
  end

  @doc """
  Verifies a signed artifact token, returning the session ID.

  ## Options

    * `:max_age` — maximum token age in seconds (default: 86400 = 24 hours)

  ## Examples

      {:ok, session_id} = URL.verify_token(conn, token)
      {:error, :expired} = URL.verify_token(conn, token, max_age: 1)
  """
  @spec verify_token(
          atom() | Plug.Conn.t() | Phoenix.LiveView.Socket.t(),
          String.t(),
          keyword()
        ) ::
          {:ok, String.t()} | {:error, :expired | :invalid}
  def verify_token(endpoint, token, opts \\ []) do
    max_age = Keyword.get(opts, :max_age, 86_400)
    Phoenix.Token.verify(endpoint, @salt, token, max_age: max_age)
  end

  @doc """
  Builds a full artifact URL path with a signed token.

  ## Examples

      url = URL.artifact_url(socket.endpoint, session_id, "dashboard.html")
      # => "/omni_artifacts/SFMyNT.../dashboard.html"
  """
  @spec artifact_url(
          atom() | Plug.Conn.t() | Phoenix.LiveView.Socket.t(),
          String.t(),
          String.t()
        ) ::
          String.t()
  def artifact_url(endpoint, session_id, filename) do
    token = sign_token(endpoint, session_id)
    "#{url_prefix()}/#{token}/#{URI.encode(filename)}"
  end

  defp url_prefix do
    Application.get_env(:omni_ui, OmniUI.Artifacts, [])
    |> Keyword.get(:url_prefix, "/omni_artifacts")
  end
end
