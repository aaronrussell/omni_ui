defmodule OmniUI.AgentLive.Agent do
  @moduledoc """
  Custom `Omni.Agent` module used by `OmniUI.AgentLive`.

  Bakes in the artifacts and REPL tools at agent-init time, reading the
  session id from `state.private.omni.session_id` (set by
  `Omni.Session` when it starts the agent).

  Consumer-provided tools (passed through `OmniUI.init_session/2`) are
  preserved — the artifacts/REPL tools are appended.
  """

  use Omni.Agent

  alias OmniUI.Artifacts
  alias OmniUI.REPL

  @impl Omni.Agent
  def init(state) do
    session_id = state.private.omni.session_id

    extras = [
      Artifacts.Tool.new(session_id: session_id),
      REPL.Tool.new(extensions: [{Artifacts.REPLExtension, session_id: session_id}])
    ]

    {:ok, %{state | tools: state.tools ++ extras}}
  end
end
