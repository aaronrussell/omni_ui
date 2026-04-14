defmodule OmniUI.Store.FileSystem do
  @moduledoc """
  Filesystem-based session store using JSON and JSONL.

  Persists conversation trees as append-only JSONL and session metadata as
  JSON. Supports incremental saves: when `:new_node_ids` is passed to
  `save_tree/3`, only those nodes are appended to `tree.jsonl` rather than
  rewriting the file.

  ## Storage layout

      priv/omni/sessions/
        {session_id}/
          tree.jsonl     # one line per tree node
          meta.json      # timestamps, title, tree path/cursors, user metadata

  With scoping (when `scope: value` is passed in opts):

      priv/omni/sessions/
        {scope}/
          {session_id}/
            tree.jsonl
            meta.json

  ## meta.json shape

      {
        "created_at": "2026-04-14T12:34:56Z",
        "updated_at": "2026-04-14T12:40:00Z",
        "title": "Session title or null",
        "path": [1, 3, 5],
        "cursors": [[1, 3], [3, 5]],
        "metadata": {"__etf": "<base64>"}
      }

  Session-level fields (`created_at`, `updated_at`, `title`, `path`,
  `cursors`) sit at the top level. User-supplied metadata lives under
  `"metadata"` as an `Omni.Codec.encode_term/1` blob, preserving full
  Elixir term fidelity. `"title"` is cached at the top level for cheap
  session listing; the canonical value is the one inside the metadata blob.

  ## Configuration

  The base path defaults to `priv/omni/sessions` relative to the current
  working directory. Override with:

      config :omni_ui, OmniUI.Store.FileSystem, base_path: "/custom/path"

  Or pass `:base_path` in the opts of any callback.
  """

  @behaviour OmniUI.Store

  alias Omni.Codec
  alias OmniUI.Tree

  @impl true
  def save_tree(session_id, %Tree{} = tree, opts \\ []) do
    dir = session_dir(session_id, opts)
    File.mkdir_p!(dir)

    write_tree_file(Path.join(dir, "tree.jsonl"), tree, Keyword.get(opts, :new_node_ids))

    update_meta(Path.join(dir, "meta.json"), %{
      path: tree.path,
      cursors: tree.cursors
    })

    :ok
  end

  @impl true
  def save_metadata(session_id, metadata, opts \\ []) when is_list(metadata) do
    dir = session_dir(session_id, opts)
    File.mkdir_p!(dir)

    meta_path = Path.join(dir, "meta.json")
    existing = read_meta(meta_path)
    merged_metadata = Keyword.merge(existing.metadata, metadata)

    update_meta(meta_path, %{metadata: merged_metadata})
    :ok
  end

  @impl true
  def load(session_id, opts \\ []) do
    dir = session_dir(session_id, opts)
    tree_path = Path.join(dir, "tree.jsonl")
    meta_path = Path.join(dir, "meta.json")

    tree_exists? = File.exists?(tree_path)
    meta_exists? = File.exists?(meta_path)

    if not tree_exists? and not meta_exists? do
      {:error, :not_found}
    else
      meta = read_meta(meta_path)
      tree = load_tree(tree_path, meta, tree_exists?)
      {:ok, tree, meta.metadata}
    end
  end

  @impl true
  def list(opts \\ []) do
    base = scoped_base(opts)
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit)

    sessions =
      case File.ls(base) do
        {:ok, entries} ->
          entries
          |> Enum.map(&read_summary(base, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
          |> Enum.drop(offset)
          |> maybe_take(limit)

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

  # ── Tree file ──────────────────────────────────────────────────────

  defp write_tree_file(path, %Tree{nodes: nodes}, nil) do
    lines =
      nodes
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.map(&encode_node/1)

    File.write!(path, Enum.map(lines, &(&1 <> "\n")))
  end

  defp write_tree_file(path, %Tree{nodes: nodes}, new_ids) when is_list(new_ids) do
    lines =
      new_ids
      |> Enum.map(&Map.fetch!(nodes, &1))
      |> Enum.map(&(encode_node(&1) <> "\n"))

    File.write!(path, lines, [:append])
  end

  defp encode_node(node) do
    JSON.encode!(%{
      "id" => node.id,
      "parent_id" => node.parent_id,
      "message" => Codec.encode(node.message),
      "usage" => if(node.usage, do: Codec.encode(node.usage), else: nil)
    })
  end

  defp load_tree(_path, _meta, false), do: %Tree{}

  defp load_tree(path, meta, true) do
    nodes =
      path
      |> File.stream!()
      |> Enum.map(&decode_node/1)

    Tree.new(nodes: nodes, path: meta.path, cursors: meta.cursors)
  end

  defp decode_node(line) do
    map = JSON.decode!(line)
    {:ok, message} = Codec.decode(map["message"])

    usage =
      case map["usage"] do
        nil -> nil
        encoded -> with {:ok, u} <- Codec.decode(encoded), do: u
      end

    %{
      id: map["id"],
      parent_id: map["parent_id"],
      message: message,
      usage: usage
    }
  end

  # ── Meta file ──────────────────────────────────────────────────────

  defp update_meta(path, updates) do
    now = DateTime.utc_now()

    base =
      case read_meta_file(path) do
        {:ok, meta} -> %{meta | updated_at: now}
        :error -> %{created_at: now, updated_at: now, path: [], cursors: %{}, metadata: []}
      end

    meta = Map.merge(base, updates)
    File.write!(path, encode_meta(meta))
  end

  defp read_meta(path) do
    case read_meta_file(path) do
      {:ok, meta} -> meta
      :error -> %{created_at: nil, updated_at: nil, path: [], cursors: %{}, metadata: []}
    end
  end

  defp read_meta_file(path) do
    case File.read(path) do
      {:ok, json} -> {:ok, decode_meta(json)}
      {:error, _} -> :error
    end
  end

  defp encode_meta(meta) do
    JSON.encode!(%{
      "title" => Keyword.get(meta.metadata, :title),
      "path" => meta.path,
      "cursors" => encode_cursors(meta.cursors),
      "metadata" => Codec.encode_term(meta.metadata),
      "created_at" => DateTime.to_iso8601(meta.created_at),
      "updated_at" => DateTime.to_iso8601(meta.updated_at)
    })
  end

  defp decode_meta(json) do
    map = JSON.decode!(json)
    {:ok, metadata} = Codec.decode_term(map["metadata"])

    %{
      created_at: decode_datetime(map["created_at"]),
      updated_at: decode_datetime(map["updated_at"]),
      path: map["path"] || [],
      cursors: decode_cursors(map["cursors"] || []),
      metadata: metadata
    }
  end

  defp decode_datetime(str) do
    {:ok, dt, _} = DateTime.from_iso8601(str)
    dt
  end

  defp encode_cursors(cursors), do: Enum.map(cursors, fn {k, v} -> [k, v] end)
  defp decode_cursors(list), do: Map.new(list, fn [k, v] -> {k, v} end)

  # ── Listing ────────────────────────────────────────────────────────

  defp read_summary(base, entry) do
    meta_path = Path.join([base, entry, "meta.json"])

    case File.read(meta_path) do
      {:ok, json} ->
        map = JSON.decode!(json)

        %{
          id: entry,
          title: map["title"],
          created_at: decode_datetime(map["created_at"]),
          updated_at: decode_datetime(map["updated_at"])
        }

      {:error, _} ->
        nil
    end
  end

  defp maybe_take(list, nil), do: list
  defp maybe_take(list, limit), do: Enum.take(list, limit)

  # ── Paths ──────────────────────────────────────────────────────────

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
end
