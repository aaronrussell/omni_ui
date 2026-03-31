defmodule OmniUI.Artifacts.Artifact do
  @moduledoc """
  Metadata for a session artifact (a file created by the agent).

  Content lives on disk; this struct is a lightweight cached view used in
  assigns. Recover the full set by scanning the artifacts directory with
  `OmniUI.Artifacts.FileSystem.list/1`.
  """

  defstruct [:filename, :mime_type, :size, :updated_at]

  @type t :: %__MODULE__{
          filename: String.t(),
          mime_type: String.t(),
          size: non_neg_integer(),
          updated_at: DateTime.t()
        }

  @doc "Builds an artifact struct from a keyword list or map."
  @spec new(Enumerable.t()) :: t()
  def new(attrs) do
    %{filename: filename} = attrs = Map.new(attrs)

    attrs
    |> Map.put_new_lazy(:mime_type, fn -> MIME.from_path(filename) end)
    |> Map.put_new_lazy(:updated_at, &DateTime.utc_now/0)
    |> then(&struct!(__MODULE__, &1))
  end

  @doc """
  Builds an artifact struct from a filename and `File.Stat`.

  The stat must use posix time (`File.stat(path, time: :posix)`).
  MIME type is derived from the file extension via the `mime` library.
  """
  @spec new(String.t(), File.Stat.t()) :: t()
  def new(filename, %File.Stat{} = stat) do
    new(
      filename: filename,
      size: stat.size,
      updated_at: DateTime.from_unix!(stat.mtime)
    )
  end
end
