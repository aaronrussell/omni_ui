defmodule OmniUI.SessionCase do
  @moduledoc """
  Test case for OmniUI tests that drive `Omni.Session.Manager` and
  `Omni.Session` processes.

  Each test gets a unique Manager registered under a fresh atom, a
  per-test FileSystem store backed by ExUnit's `@moduletag :tmp_dir`,
  and helpers for stubbing the LLM HTTP path with `Req.Test`.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Omni.Session
      alias Omni.Session.Manager
      alias Omni.Session.Store.FileSystem

      @text_fixture "test/support/fixtures/anthropic_text.sse"
      @title_fixture "test/support/fixtures/anthropic_title.sse"

      defp model do
        {:ok, model} = Omni.get_model(:anthropic, "claude-haiku-4-5")
        model
      end

      defp tmp_store(%{tmp_dir: dir}), do: {FileSystem, base_path: dir}
      defp tmp_store(_), do: raise("OmniUI.SessionCase tests require @moduletag :tmp_dir")

      defp unique_name(prefix \\ "TM") do
        String.to_atom(
          "Elixir.OmniUI.SessionCaseTest.#{prefix}#{System.unique_integer([:positive])}"
        )
      end

      defp unique_stub_name do
        :"omni_ui_test_#{System.unique_integer([:positive])}"
      end

      defp stub_fixture(stub_name, fixture_path) do
        Req.Test.stub(stub_name, fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, File.read!(fixture_path))
        end)
      end

      defp stub_sequence(stub_name, fixtures) do
        {:ok, counter} = Elixir.Agent.start_link(fn -> 0 end)

        Req.Test.stub(stub_name, fn conn ->
          call_num = Elixir.Agent.get_and_update(counter, fn n -> {n, n + 1} end)
          fixture = Enum.at(fixtures, call_num, List.last(fixtures))

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, File.read!(fixture))
        end)
      end

      defp stub_opts(stub_name), do: [api_key: "test-key", plug: {Req.Test, stub_name}]

      defp start_manager!(ctx, opts \\ []) do
        name = opts[:name] || unique_name("Mgr")
        store = opts[:store] || tmp_store(ctx)

        start_supervised!({Manager, name: name, store: store})

        name
      end

      defp create_session!(manager, opts) do
        {:ok, pid} = Manager.create(manager, opts)
        pid
      end

      # Polls `fun` every 10ms up to `timeout` ms. Use for races where
      # a downstream side-effect (e.g. the title service writing back
      # to a session after a turn commit) must land after the primary
      # event has already been observed.
      defp eventually(fun, timeout \\ 500) do
        deadline = System.monotonic_time(:millisecond) + timeout
        do_eventually(fun, deadline)
      end

      defp do_eventually(fun, deadline) do
        cond do
          fun.() ->
            true

          System.monotonic_time(:millisecond) > deadline ->
            false

          true ->
            Process.sleep(10)
            do_eventually(fun, deadline)
        end
      end
    end
  end
end
