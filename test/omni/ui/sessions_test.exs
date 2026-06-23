defmodule Omni.UI.SessionsTest do
  use ExUnit.Case, async: false

  alias Omni.UI.Sessions

  @session_id "sess-abc-123"

  setup do
    prev = Application.get_env(:omni_ui, Sessions)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:omni_ui, Sessions, prev),
        else: Application.delete_env(:omni_ui, Sessions)
    end)

    :ok
  end

  describe "session_dir/1" do
    test "joins the base dir with the session ID" do
      Application.put_env(:omni_ui, Sessions, sessions_base_dir: "/data/sessions")

      assert Sessions.session_dir(@session_id) == "/data/sessions/sess-abc-123"
    end

    test "raises when :sessions_base_dir is missing" do
      Application.put_env(:omni_ui, Sessions, [])

      assert_raise ArgumentError, ~r/missing :sessions_base_dir/, fn ->
        Sessions.session_dir(@session_id)
      end
    end

    test "raises when config key is absent entirely" do
      Application.delete_env(:omni_ui, Sessions)

      assert_raise ArgumentError, ~r/missing :sessions_base_dir/, fn ->
        Sessions.session_dir(@session_id)
      end
    end
  end

  describe "session_files_dir/1" do
    test "appends 'files' to the session dir" do
      Application.put_env(:omni_ui, Sessions, sessions_base_dir: "/data/sessions")

      assert Sessions.session_files_dir(@session_id) ==
               "/data/sessions/sess-abc-123/files"
    end
  end
end
