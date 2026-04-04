defmodule OmniUI.Store.Filesystem do
  @moduledoc """
  Filesystem-based session store using Erlang Term Format (ETF).

  A development adapter that persists conversation trees and metadata
  as binary ETF files. Each session gets its own directory containing
  `tree.etf` and `meta.etf`.

  ## Storage layout

      priv/omni/sessions/
        {session_id}/
          tree.etf       # %OmniUI.Tree{} struct
          meta.etf       # %{created_at, updated_at, metadata: keyword()}

  With scoping (when `scope: value` is passed in opts):

      priv/omni/sessions/
        {scope}/
          {session_id}/
            tree.etf
            meta.etf

  ## Configuration

  The base path defaults to `priv/omni/sessions` relative to the current
  working directory (i.e. the host application root). Override with:

      config :omni_ui, OmniUI.Store.Filesystem, base_path: "/custom/path"

  Or pass `:base_path` in the opts of any callback.
  """

  @behaviour OmniUI.Store

  @impl true
  def save_tree(session_id, %OmniUI.Tree{} = tree, opts \\ []) do
    dir = session_dir(session_id, opts)
    File.mkdir_p!(dir)

    File.write!(Path.join(dir, "tree.etf"), :erlang.term_to_binary(tree))

    meta_path = Path.join(dir, "meta.etf")
    now = DateTime.utc_now()

    meta =
      case read_meta(meta_path) do
        {:ok, existing} -> %{existing | updated_at: now}
        :error -> %{created_at: now, updated_at: now, metadata: []}
      end

    File.write!(meta_path, :erlang.term_to_binary(meta))

    :ok
  end

  @impl true
  def save_metadata(session_id, metadata, opts \\ []) when is_list(metadata) do
    dir = session_dir(session_id, opts)
    File.mkdir_p!(dir)

    meta_path = Path.join(dir, "meta.etf")
    now = DateTime.utc_now()

    meta =
      case read_meta(meta_path) do
        {:ok, existing} -> %{existing | metadata: metadata, updated_at: now}
        :error -> %{created_at: now, updated_at: now, metadata: metadata}
      end

    File.write!(meta_path, :erlang.term_to_binary(meta))

    :ok
  end

  @impl true
  def load(session_id, opts \\ []) do
    dir = session_dir(session_id, opts)

    with {:ok, tree_bin} <- File.read(Path.join(dir, "tree.etf")),
         {:ok, meta_bin} <- File.read(Path.join(dir, "meta.etf")) do
      tree = :erlang.binary_to_term(tree_bin)
      meta = :erlang.binary_to_term(meta_bin)
      {:ok, tree, meta.metadata}
    else
      {:error, :enoent} -> {:error, :not_found}
    end
  end

  @impl true
  def list(opts \\ []) do
    base = scoped_base(opts)

    sessions =
      case File.ls(base) do
        {:ok, entries} ->
          entries
          |> Enum.map(fn entry ->
            meta_path = Path.join([base, entry, "meta.etf"])

            case read_meta(meta_path) do
              {:ok, meta} ->
                %{
                  id: entry,
                  title: Keyword.get(meta.metadata, :title),
                  created_at: meta.created_at,
                  updated_at: meta.updated_at
                }

              :error ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})

        {:error, :enoent} ->
          []
      end

    {:ok, sessions}
  end

  @impl true
  def delete(session_id, opts \\ []) do
    dir = session_dir(session_id, opts)

    case File.rm_rf(dir) do
      {:ok, _} -> :ok
      {:error, reason, _} -> {:error, reason}
    end
  end

  # ── Private ────────────────────────────────────────────────────────

  defp session_dir(session_id, opts) do
    Path.join(scoped_base(opts), session_id)
  end

  defp scoped_base(opts) do
    base = base_path(opts)

    case Keyword.get(opts, :scope) do
      nil -> base
      scope -> Path.join(base, to_string(scope))
    end
  end

  defp base_path(opts) do
    Keyword.get_lazy(opts, :base_path, fn ->
      Application.get_env(:omni_ui, __MODULE__, [])
      |> Keyword.get(:base_path, default_base_path())
    end)
  end

  defp default_base_path do
    Path.join("priv", "omni/sessions")
  end

  defp read_meta(path) do
    case File.read(path) do
      {:ok, bin} -> {:ok, :erlang.binary_to_term(bin)}
      {:error, _} -> :error
    end
  end
end
