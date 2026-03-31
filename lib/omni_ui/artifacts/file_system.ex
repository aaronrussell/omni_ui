defmodule OmniUI.Artifacts.FileSystem do
  @moduledoc """
  Filesystem operations for session artifacts.

  All functions take `dir` (the artifacts directory path) as the first argument.
  Filenames are validated to prevent directory traversal and other unsafe paths.
  """

  alias OmniUI.Artifacts.Artifact

  @doc """
  Writes content to an artifact file (upsert).

  Creates the artifacts directory if it doesn't exist.
  """
  @spec write(String.t(), String.t(), String.t()) :: {:ok, Artifact.t()} | {:error, String.t()}
  def write(dir, filename, content) do
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
  @spec read(String.t(), String.t()) :: {:ok, binary()} | {:error, String.t()}
  def read(dir, filename) do
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
  @spec patch(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, Artifact.t()} | {:error, String.t()}
  def patch(dir, filename, search, replace) do
    with :ok <- validate_filename(filename),
         {:ok, content} <- read(dir, filename) do
      if String.contains?(content, search) do
        updated = String.replace(content, search, replace, global: false)
        write(dir, filename, updated)
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
  @spec list(String.t()) :: {:ok, [Artifact.t()]}
  def list(dir) do
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
  @spec delete(String.t(), String.t()) :: :ok | {:error, String.t()}
  def delete(dir, filename) do
    with :ok <- validate_filename(filename) do
      case File.rm(Path.join(dir, filename)) do
        :ok -> :ok
        {:error, :enoent} -> {:error, "artifact not found: #{filename}"}
        {:error, posix} -> {:error, "failed to delete #{filename}: #{posix}"}
      end
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
