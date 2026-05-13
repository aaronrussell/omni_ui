defmodule OmniUI.AgentLive.Agent do
  @moduledoc """
  Custom `Omni.Agent` module used by `OmniUI.AgentLive`.

  Bakes in the files, REPL, and web-fetch tools at agent-init time,
  reading the session id from `state.private.omni.session_id` (set by
  `Omni.Session` when it starts the agent).

  Consumer-provided tools (passed through `OmniUI.init_session/2`) are
  preserved — the built-in tools are appended.
  """

  use Omni.Agent
  alias Omni.Tools.Files.FS

  @impl Omni.Agent
  def init(state) do
    session_id = state.private.omni.session_id

    files_dir = OmniUI.Sessions.session_files_dir(session_id)
    fs = FS.new(base_dir: files_dir, nested: false)

    extras = [
      Omni.Tools.Files.new(base_dir: files_dir, nested: false),
      Omni.Tools.Repl.new(extensions: [{Omni.Tools.Repl.Extensions.Files, fs: fs}]),
      Omni.Tools.WebFetch.new()
    ]

    {:ok, %{state | tools: state.tools ++ extras}}
  end
end
