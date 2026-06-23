defmodule Omni.UI.Test.StubSession do
  @moduledoc false
  use GenServer

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)

  @impl GenServer
  def init(opts), do: {:ok, Map.new(opts)}

  @impl GenServer
  def handle_call({:navigate, _node_id}, _from, state) do
    {:reply, Map.get(state, :navigate, :ok), state}
  end

  def handle_call({:prompt, _content, _opts}, _from, state) do
    {:reply, Map.get(state, :prompt, :ok), state}
  end

  def handle_call({:branch, _node_id}, _from, state) do
    {:reply, Map.get(state, :branch, :ok), state}
  end

  def handle_call({:branch, _node_id, _content}, _from, state) do
    {:reply, Map.get(state, :branch, :ok), state}
  end

  def handle_call({:set_agent, _key, _value}, _from, state) do
    {:reply, :ok, state}
  end
end
