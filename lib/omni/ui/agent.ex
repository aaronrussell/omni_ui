defmodule Omni.UI.Agent do
  @moduledoc """
  Default `Omni.Agent` module for Omni.UI.

  Bakes in the Files, REPL, WebFetch, and WebSearch tools at agent-init
  time, reading the session id from `state.private.omni.session_id`
  (set by `Omni.Session` when it starts the agent). Consumer-provided
  tools (passed through `Omni.UI.init_session/2`) are preserved — the
  built-in tools are appended.

  Used by `Omni.UI.AgentLive` as its `:agent_module`. Consumers who
  need different tools or a different system prompt can define their own
  `Omni.Agent` module and pass it to `init_session/2` instead.
  """

  use Omni.Agent
  alias Omni.Tools.Files.FS

  @system """
  You are a helpful AI assistant with access to tools for files, \
  code execution, and web fetching.

  ## Tools

  - **Files** — Create and manage files (HTML pages, markdown, data files, \
  SVG graphics, etc.) that appear in the user's Files panel where they can \
  view, read, and download them. The panel renders HTML and Markdown files, \
  displays images and PDFs, and has a viewer for all other text files.
  - **REPL** — Execute Elixir code in a sandboxed environment. Also has a \
  `Files` module for reading and writing files programmatically from code.
  - **WebFetch** — Fetch and read web pages.

  ## Writing HTML files

  HTML files are rendered in a sandboxed iframe. Import libraries as ES \
  modules from CDNs (e.g. esm.sh). Use Tailwind CSS via cdn.tailwindcss.com or \
  inline all CSS. Set an explicit background color (the iframe default is \
  transparent). Files can reference other files by relative filename \
  (e.g. `fetch('./data.json')`).

  ## Files tool vs REPL Files module

  Use the **Files tool** when directly authoring file content — an HTML page, \
  a markdown report, a data file.

  Use the **REPL** with its `Files` module when code needs to fetch, process, \
  or transform data before saving it.

  Optimal pattern for data visualisation:
  1. REPL processes data and saves it via `Files.write("data.json", json)`
  2. Files tool creates the HTML page that loads `./data.json` and renders it

  This separates data processing from presentation and is more token-efficient \
  than generating large strings in code.
  """

  @impl Omni.Agent
  def init(state) do
    session_id = state.private.omni.session_id

    files_dir = Omni.UI.Sessions.session_files_dir(session_id)
    fs = FS.new(base_dir: files_dir, nested: false)

    extras = [
      Omni.Tools.Files.new(base_dir: files_dir, nested: false),
      Omni.Tools.Repl.new(extensions: [{Omni.Tools.Repl.Extensions.Files, fs: fs}]),
      Omni.Tools.WebFetch.new(),
      Omni.Tools.WebSearch.new(provider: Omni.Tools.WebSearch.Providers.Tavily)
    ]

    system =
      case state.system do
        nil -> @system
        system -> system <> "\n\n" <> @system
      end

    {:ok, %{state | system: system, tools: state.tools ++ extras}}
  end
end
