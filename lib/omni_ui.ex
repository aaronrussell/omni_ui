defmodule OmniUI do
  @moduledoc """
  OmniUI adds agent chat capabilities to any LiveView.

  Provides `start_agent/2` for initialising the agent system in `mount/3`,
  and `update_agent/2` for modifying agent configuration at runtime.
  """

  import Phoenix.Component
  import Phoenix.LiveView, only: [stream: 3]

  @doc """
  Initialises the OmniUI agent system on a socket.

  Called in `mount/3`. Returns the socket with all OmniUI assigns populated
  and the `:turns` stream initialised.

  ## Options

    * `:model` (required) — `%Omni.Model{}` struct or `{provider_id, model_id}` tuple
    * `:tree` — `%OmniUI.Tree{}` to restore a conversation (default: empty tree)
    * `:thinking` — thinking mode: `false | :low | :medium | :high | :max` (default: `false`)
    * `:system` — system prompt string (default: `nil`)
    * `:tools` — list of tool modules (default: `[]`)
    * `:model_options` — list of `%Omni.Model{}` structs for the model selector (default: `[]`)

  ## Example

      def mount(_params, _session, socket) do
        {:ok, start_agent(socket,
          model: {:anthropic, "claude-sonnet-4-20250514"},
          system: "You are a helpful assistant.",
          thinking: :high
        )}
      end
  """
  @spec start_agent(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def start_agent(socket, opts) do
    model = resolve_model!(Keyword.fetch!(opts, :model))
    tree = Keyword.get(opts, :tree, %OmniUI.Tree{})
    thinking = Keyword.get(opts, :thinking, false)
    system = Keyword.get(opts, :system)
    tools = Keyword.get(opts, :tools, [])
    model_options = Keyword.get(opts, :model_options, [])

    agent_opts =
      [model: model, messages: OmniUI.Tree.messages(tree), opts: [thinking: thinking]]
      |> maybe_put(:system, system)
      |> maybe_put(:tools, tools)

    {:ok, agent} = Omni.Agent.start_link(agent_opts)

    turns = OmniUI.Turn.all(tree)
    usage = OmniUI.Tree.usage(tree)

    socket
    |> assign(
      agent: agent,
      tree: tree,
      current_turn: nil,
      model: model,
      model_options: model_options,
      thinking: thinking,
      usage: usage
    )
    |> stream(:turns, turns)
  end

  @doc """
  Updates agent configuration on a running system.

  Accepts any subset of options. For each provided option, updates the
  appropriate combination of socket assign and agent state.

  ## Options

    * `:model` — updates both socket assign and agent model
    * `:thinking` — updates both socket assign and agent opts
    * `:system` — updates agent context only (not surfaced in UI)
    * `:tools` — updates agent context only
    * `:model_options` — updates socket assign only

  ## Example

      OmniUI.update_agent(socket, model: {:anthropic, "claude-opus-4-20250514"})
  """
  @spec update_agent(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def update_agent(socket, opts) do
    agent = socket.assigns.agent

    Enum.reduce(opts, socket, fn
      {:model, value}, socket ->
        model = resolve_model!(value)
        :ok = Omni.Agent.set_state(agent, :model, model)
        assign(socket, :model, model)

      {:thinking, thinking}, socket ->
        :ok = Omni.Agent.set_state(agent, :opts, &Keyword.put(&1, :thinking, thinking))
        assign(socket, :thinking, thinking)

      {:system, system}, socket ->
        :ok = Omni.Agent.set_state(agent, :context, &%{&1 | system: system})
        socket

      {:tools, tools}, socket ->
        :ok = Omni.Agent.set_state(agent, :context, &%{&1 | tools: tools})
        socket

      {:model_options, model_options}, socket ->
        assign(socket, :model_options, model_options)
    end)
  end

  # -- Private ---------------------------------------------------------------

  defp resolve_model!(%Omni.Model{} = model), do: model

  defp resolve_model!({provider_id, model_id}) do
    case Omni.get_model(provider_id, model_id) do
      {:ok, model} -> model
      {:error, reason} -> raise ArgumentError, "failed to resolve model: #{inspect(reason)}"
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, []), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
