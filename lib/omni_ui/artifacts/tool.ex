defmodule OmniUI.Artifacts.Tool do
  @moduledoc """
  Omni tool for creating and managing session artifacts.

  Artifacts are files persisted in the session's artifacts directory. The tool
  supports five commands: `write`, `patch`, `get`, `list`, and `delete`.

  ## Usage

      tool = OmniUI.Artifacts.Tool.new(session_id: session_id)

  Then add the tool to the agent via `Omni.Agent.add_tools/2`.

  Path resolution and configuration are handled by `OmniUI.Artifacts.FileSystem`.
  """

  use Omni.Tool,
    name: "artifacts",
    description: """
    Create and manage artifacts — persistent files that live alongside the conversation.

    Artifacts are files you author directly: markdown notes, HTML pages, data files, \
    reports, code files, SVG graphics. The user can view or download them.

    ## Commands
    - write: Create or replace an artifact. Requires `filename` and `content`.
    - patch: Targeted find-and-replace edit. Requires `filename`, `search`, `replace`. \
    Only the first occurrence is replaced.
    - get: Read artifact content. Requires `filename`.
    - list: List all artifacts with MIME types and sizes.
    - delete: Remove an artifact. Requires `filename`.

    ## Prefer patch over write
    When editing an existing artifact, always prefer patch for targeted changes. \
    Only use write to replace an entire file when most of the content is changing. \
    Ask yourself: can I describe the change as search → replace? If yes, use patch.

    ## Filenames
    Simple names only (e.g. 'report.html', 'data.json'). No path separators, \
    no leading dots, no '..' sequences.

    ## HTML artifacts
    HTML artifacts are rendered in a sandboxed iframe for the user.
    - Must be self-contained single files.
    - Import libraries as ES modules from CDNs (e.g. esm.sh).
    - Set an explicit background color (iframe default is transparent).
    - Inline all CSS or use a CSS framework CDN.
    - Can reference other artifacts by relative filename (e.g. fetch('./data.json')).

    ## Artifacts vs REPL
    Use this tool when you are directly authoring file content (HTML pages, notes, \
    reports). Use the REPL tool when code needs to fetch, process, or transform data.

    Optimal pattern for data visualisation:
    1. REPL fetches/processes data → saves result as data.json via Artifacts module
    2. This tool creates the HTML page that loads ./data.json and renders it

    This separates data processing (code) from presentation (authored content), \
    and is more token-efficient than generating HTML strings in code.\
    """

  alias OmniUI.Artifacts.FileSystem

  @impl Omni.Tool
  def schema do
    import Omni.Schema

    object(
      %{
        command:
          enum(
            ["write", "patch", "get", "list", "delete"],
            description: "The operation to perform"
          ),
        filename:
          string(description: "Filename including extension (e.g. 'report.html', 'data.json')"),
        content: string(description: "File content"),
        search: string(description: "String to find (for patch command)"),
        replace: string(description: "Replacement string (for patch command)")
      },
      required: [:command]
    )
  end

  @impl Omni.Tool
  def init(opts) do
    _session_id = Keyword.fetch!(opts, :session_id)
    opts
  end

  @impl Omni.Tool
  def call(%{command: "write", filename: filename, content: content}, opts) do
    case FileSystem.write(filename, content, opts) do
      {:ok, artifact} -> "Wrote #{filename} (#{artifact.size} bytes)"
      {:error, reason} -> raise reason
    end
  end

  def call(%{command: "patch", filename: filename, search: search, replace: replace}, opts) do
    case FileSystem.patch(filename, search, replace, opts) do
      {:ok, artifact} -> "Patched #{filename} (#{artifact.size} bytes)"
      {:error, reason} -> raise reason
    end
  end

  def call(%{command: "get", filename: filename}, opts) do
    case FileSystem.read(filename, opts) do
      {:ok, content} -> content
      {:error, reason} -> raise reason
    end
  end

  def call(%{command: "list"}, opts) do
    {:ok, artifacts} = FileSystem.list(opts)

    case artifacts do
      [] ->
        "No artifacts"

      artifacts ->
        Enum.map_join(artifacts, "\n", fn a ->
          "#{a.filename} (#{a.mime_type}, #{a.size} bytes)"
        end)
    end
  end

  def call(%{command: "delete", filename: filename}, opts) do
    case FileSystem.delete(filename, opts) do
      :ok -> "Deleted #{filename}"
      {:error, reason} -> raise reason
    end
  end
end
