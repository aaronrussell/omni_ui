defmodule OmniUI.Artifacts.FileSystem do
  @moduledoc """
  Filesystem operations for session artifacts.

  All functions accept an `opts` keyword list as the final argument with:

    * `:session_id` (required) — the session identifier
    * `:base_path` — override base path (default: app config or `priv/omni/sessions`)

  The full artifacts directory is resolved as `{base_path}/{session_id}/artifacts/`.

  ## Configuration

  The base path defaults to `priv/omni/sessions` within the `:omni_ui`
  application directory (the same default as `OmniUI.Store.Filesystem`).
  Override with:

      config :omni_ui, OmniUI.Artifacts, base_path: "/custom/path"
  """

  alias OmniUI.Artifacts.Artifact

  @doc """
  Returns the resolved base path for artifact storage.

  Checks (in order): explicit `:base_path` in opts, application config
  (`config :omni_ui, OmniUI.Artifacts, base_path: "..."`), then falls back
  to `priv/omni/sessions` within the `:omni_ui` application directory.
  """
  @spec base_path(keyword()) :: String.t()
  def base_path(opts) do
    Keyword.get_lazy(opts, :base_path, fn ->
      Application.get_env(:omni_ui, OmniUI.Artifacts, [])
      |> Keyword.get(:base_path, default_base_path())
    end)
  end

  @doc """
  Returns the resolved artifacts directory path for a session.

  ## Options

    * `:session_id` (required) — the session identifier
    * `:base_path` — override base path (default: app config or `priv/omni/sessions`)
  """
  @spec artifacts_dir(keyword()) :: String.t()
  def artifacts_dir(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    base = base_path(opts)
    Path.join([base, session_id, "artifacts"])
  end

  @doc """
  Writes content to an artifact file (upsert).

  Creates the artifacts directory if it doesn't exist.
  """
  @spec write(String.t(), String.t(), keyword()) :: {:ok, Artifact.t()} | {:error, String.t()}
  def write(filename, content, opts) do
    dir = artifacts_dir(opts)

    with :ok <- validate_filename(filename),
         :ok <- File.mkdir_p(dir),
         :ok <- File.write(Path.join(dir, filename), content) do
      {:ok, Artifact.new(filename: filename, size: byte_size(content))}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, posix} -> {:error, "failed to write #{filename}: #{posix}"}
    end
  end

  @doc "Reads the content of an artifact file."
  @spec read(String.t(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def read(filename, opts) do
    dir = artifacts_dir(opts)

    with :ok <- validate_filename(filename) do
      case File.read(Path.join(dir, filename)) do
        {:ok, _content} = ok -> ok
        {:error, :enoent} -> {:error, "artifact not found: #{filename}"}
        {:error, posix} -> {:error, "failed to read #{filename}: #{posix}"}
      end
    end
  end

  @doc """
  Applies a find-replace edit to an artifact file.

  Replaces only the first occurrence of `search`. Returns an error if the
  search string is not found in the file.
  """
  @spec patch(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Artifact.t()} | {:error, String.t()}
  def patch(filename, search, replace, opts) do
    dir = artifacts_dir(opts)

    with :ok <- validate_filename(filename),
         {:ok, content} <- read_file(dir, filename) do
      if String.contains?(content, search) do
        updated = String.replace(content, search, replace, global: false)
        write_file(dir, filename, updated)
      else
        {:error, "search string not found in #{filename}"}
      end
    end
  end

  @doc """
  Lists all artifacts in the directory.

  Ignores dotfiles and subdirectories. Returns `{:ok, []}` if the directory
  doesn't exist yet.
  """
  @spec list(keyword()) :: {:ok, [Artifact.t()]}
  def list(opts) do
    dir = artifacts_dir(opts)

    case File.ls(dir) do
      {:ok, entries} ->
        artifacts =
          entries
          |> Enum.reject(&String.starts_with?(&1, "."))
          |> Enum.filter(&File.regular?(Path.join(dir, &1)))
          |> Enum.flat_map(fn name ->
            case File.stat(Path.join(dir, name), time: :posix) do
              {:ok, stat} -> [Artifact.new(name, stat)]
              {:error, _} -> []
            end
          end)
          |> Enum.sort_by(& &1.filename)

        {:ok, artifacts}

      {:error, :enoent} ->
        {:ok, []}
    end
  end

  @doc "Deletes an artifact file."
  @spec delete(String.t(), keyword()) :: :ok | {:error, String.t()}
  def delete(filename, opts) do
    dir = artifacts_dir(opts)

    with :ok <- validate_filename(filename) do
      case File.rm(Path.join(dir, filename)) do
        :ok -> :ok
        {:error, :enoent} -> {:error, "artifact not found: #{filename}"}
        {:error, posix} -> {:error, "failed to delete #{filename}: #{posix}"}
      end
    end
  end

  # ── Private ────────────────────────────────────────────────────────

  # Direct file operations used internally by patch to avoid
  # double path resolution.

  defp read_file(dir, filename) do
    case File.read(Path.join(dir, filename)) do
      {:ok, _content} = ok -> ok
      {:error, :enoent} -> {:error, "artifact not found: #{filename}"}
      {:error, posix} -> {:error, "failed to read #{filename}: #{posix}"}
    end
  end

  defp write_file(dir, filename, content) do
    case File.write(Path.join(dir, filename), content) do
      :ok -> {:ok, Artifact.new(filename: filename, size: byte_size(content))}
      {:error, posix} -> {:error, "failed to write #{filename}: #{posix}"}
    end
  end

  defp default_base_path do
    case :code.priv_dir(:omni_ui) do
      {:error, :bad_name} -> Path.join("priv", "omni/sessions")
      dir -> Path.join(to_string(dir), "omni/sessions")
    end
  end

  defp validate_filename(filename) do
    cond do
      filename == "" -> {:error, "filename must not be empty"}
      String.contains?(filename, "/") -> {:error, "filename must not contain path separators"}
      String.contains?(filename, "\\") -> {:error, "filename must not contain path separators"}
      String.contains?(filename, "..") -> {:error, "filename must not contain '..'"}
      String.contains?(filename, <<0>>) -> {:error, "filename must not contain null bytes"}
      String.starts_with?(filename, ".") -> {:error, "filename must not start with '.'"}
      true -> :ok
    end
  end
end
