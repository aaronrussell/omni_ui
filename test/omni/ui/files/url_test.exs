defmodule Omni.UI.Files.URLTest.Endpoint do
  @moduledoc false
  def config(:secret_key_base), do: String.duplicate("a", 64)
end

defmodule Omni.UI.Files.URLTest do
  use ExUnit.Case, async: true

  alias Omni.UI.Files.URL
  alias Omni.UI.Files.URLTest.Endpoint

  @session_id "test-session-123"

  describe "sign_token/2 and verify_token/3" do
    test "round-trips a session ID" do
      token = URL.sign_token(Endpoint, @session_id)
      assert {:ok, @session_id} = URL.verify_token(Endpoint, token)
    end

    test "returns error for tampered token" do
      assert {:error, :invalid} = URL.verify_token(Endpoint, "garbage")
    end

    test "returns error for expired token" do
      token = URL.sign_token(Endpoint, @session_id)
      assert {:error, :expired} = URL.verify_token(Endpoint, token, max_age: 0)
    end
  end

  describe "file_url/3" do
    test "builds a URL with the default prefix" do
      url = URL.file_url(Endpoint, @session_id, "report.html")

      assert String.starts_with?(url, "/omni_files/")
      assert String.ends_with?(url, "/report.html")
    end

    test "URI-encodes the filename" do
      url = URL.file_url(Endpoint, @session_id, "my file (1).html")

      assert url =~ "/my%20file%20(1).html"
      refute url =~ " "
    end

    test "embeds a valid token" do
      url = URL.file_url(Endpoint, @session_id, "page.html")
      [_prefix, token, _filename] = url |> String.trim_leading("/") |> String.split("/", parts: 3)

      assert {:ok, @session_id} = URL.verify_token(Endpoint, token)
    end

    test "respects a custom :files_url_prefix" do
      prev = Application.get_env(:omni_ui, :files_url_prefix)
      Application.put_env(:omni_ui, :files_url_prefix, "/custom/files")

      on_exit(fn ->
        if prev,
          do: Application.put_env(:omni_ui, :files_url_prefix, prev),
          else: Application.delete_env(:omni_ui, :files_url_prefix)
      end)

      url = URL.file_url(Endpoint, @session_id, "page.html")
      assert String.starts_with?(url, "/custom/files/")
    end
  end
end
