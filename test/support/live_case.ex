defmodule Omni.UI.LiveCase do
  @moduledoc """
  Test case for full LiveView integration tests.

  Provides a `conn` and session cleanup, combining endpoint access with
  `Omni.UI.Sessions` management. The endpoint and Sessions manager are
  started in `test_helper.exs`.

  ## Usage

      use Omni.UI.LiveCase
  """

  use ExUnit.CaseTemplate

  alias Omni.UI.Sessions

  using do
    quote do
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest

      alias Omni.UI.Sessions

      @endpoint Omni.UI.TestEndpoint
    end
  end

  setup do
    baseline_open = Sessions.list_open() |> Enum.map(& &1.id) |> MapSet.new()
    {:ok, persisted} = Sessions.list()
    baseline_persisted = persisted |> Enum.map(& &1.id) |> MapSet.new()
    baseline = MapSet.union(baseline_open, baseline_persisted)

    on_exit(fn -> cleanup_sessions(baseline) end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  defp cleanup_sessions(baseline) do
    {:ok, all} = Sessions.list()

    all
    |> Enum.reject(fn %{id: id} -> MapSet.member?(baseline, id) end)
    |> Enum.each(fn %{id: id} -> Sessions.delete(id) end)

    Enum.each(Sessions.list_open(), fn %{id: id} ->
      unless MapSet.member?(baseline, id), do: Sessions.delete(id)
    end)
  end
end
