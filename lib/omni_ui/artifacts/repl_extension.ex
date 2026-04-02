defmodule OmniUI.Artifacts.REPLExtension do
  @moduledoc """
  Sandbox extension that makes artifact operations available in the REPL.

  When added to `OmniUI.REPL.Tool` as an extension, this injects an
  `Artifacts` module into the sandbox peer node with functions that delegate
  to `OmniUI.Artifacts.FileSystem`:

      Artifacts.write("chart.html", html_content)  #=> %Artifact{}
      Artifacts.read("data.csv")                    #=> "csv,content..."
      Artifacts.patch("chart.html", "old", "new")   #=> %Artifact{}
      Artifacts.list()                               #=> [%Artifact{}, ...]
      Artifacts.delete("temp.txt")                   #=> :ok

  ## Usage

      REPL.Tool.new(
        extensions: [{OmniUI.Artifacts.REPLExtension, session_id: session_id}]
      )

  The `:session_id` option is required. The base path is resolved from
  application config at tool construction time and baked into the facade
  module, so the peer node doesn't need access to host app config.
  """

  @behaviour OmniUI.REPL.SandboxExtension

  alias OmniUI.Artifacts.FileSystem

  @impl true
  def code(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    base_path = FileSystem.base_path(opts)
    fs_opts = [session_id: session_id, base_path: base_path]

    quote do
      defmodule Artifacts do
        @moduledoc false
        @opts unquote(fs_opts)

        def write(filename, content) do
          case OmniUI.Artifacts.FileSystem.write(filename, content, @opts) do
            {:ok, artifact} -> artifact
            {:error, reason} -> raise reason
          end
        end

        def read(filename) do
          case OmniUI.Artifacts.FileSystem.read(filename, @opts) do
            {:ok, content} -> content
            {:error, reason} -> raise reason
          end
        end

        def patch(filename, search, replace) do
          case OmniUI.Artifacts.FileSystem.patch(filename, search, replace, @opts) do
            {:ok, artifact} -> artifact
            {:error, reason} -> raise reason
          end
        end

        def list do
          {:ok, artifacts} = OmniUI.Artifacts.FileSystem.list(@opts)
          artifacts
        end

        def delete(filename) do
          case OmniUI.Artifacts.FileSystem.delete(filename, @opts) do
            :ok -> :ok
            {:error, reason} -> raise reason
          end
        end
      end
    end
  end

  @impl true
  def description(_opts) do
    """
    ## Artifacts (in sandbox)
    An `Artifacts` module is available for creating and managing session artifacts \
    (persistent files the user can view or download).

    - `Artifacts.write(filename, content)` — create/replace artifact, returns `%Artifact{}`
    - `Artifacts.read(filename)` — read content as string
    - `Artifacts.patch(filename, search, replace)` — find-replace edit, returns `%Artifact{}`
    - `Artifacts.list()` — list all artifacts as `[%Artifact{filename, mime_type, size, updated_at}]`
    - `Artifacts.delete(filename)` — remove artifact, returns `:ok`

    Use this when code generates or processes data that should be saved as an \
    artifact (JSON, CSV, processed data files). For authored content like HTML \
    pages, prefer the artifacts tool directly — it's more token-efficient. \
    Errors raise automatically.\
    """
  end
end
