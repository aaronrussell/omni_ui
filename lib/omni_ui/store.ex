defmodule OmniUI.Store do
  @moduledoc """
  Session persistence subsystem — both behaviour and public API.

  Consumers call this module directly:

      OmniUI.Store.save_tree(session_id, tree, opts)
      OmniUI.Store.save_metadata(session_id, metadata, opts)
      OmniUI.Store.load(session_id, opts)
      OmniUI.Store.list(opts)
      OmniUI.Store.delete(session_id, opts)

  Each function resolves the configured adapter at runtime. When no
  adapter is configured the functions are no-ops — `save_*`/`delete`
  return `:ok`, `load` returns `{:error, :not_found}`, `list` returns
  `{:ok, []}`. This makes the API safe to call from code that may run
  with or without persistence configured.

  ## Adapter configuration

      config :omni, OmniUI.Store, adapter: OmniUI.Store.FileSystem

  Or pass `:adapter` in opts to override for a specific call:

      OmniUI.Store.save_tree(id, tree, adapter: MyApp.CustomStore)

  ## Scoping

  Multi-tenant applications pass `scope: value` in opts to isolate
  sessions by user, organization, or other tenant key:

      OmniUI.Store.save_tree(id, tree, scope: current_user.id)
      OmniUI.Store.load(id, scope: current_user.id)
      OmniUI.Store.list(scope: current_user.id)

  Adapters that don't need scoping ignore the option.

  ## Implementing an adapter

  Implement the `OmniUI.Store` behaviour. All callbacks accept
  `opts :: keyword()` as an extension point for scoping, pagination,
  and adapter-specific options.

  ## Timestamps

  `created_at` and `updated_at` are managed by the adapter, not the
  caller. The adapter sets `created_at` on first save and `updated_at`
  on every save.
  """

  @type session_id :: String.t()
  @type metadata :: %{optional(atom()) => term()}
  @type adapter :: module()

  @type session_info :: %{
          id: session_id(),
          title: String.t() | nil,
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @doc """
  Save a conversation tree.

  The adapter persists the tree's nodes, active path, and cursor map.
  It manages `created_at` (set on first save) and `updated_at` (set on
  every save) internally.

  Accepts `:new_node_ids` in opts as an optimization hint. When present,
  the adapter may append only those nodes rather than rewriting the full
  node set. When absent, the adapter saves the full tree.
  """
  @callback save_tree(session_id(), OmniUI.Tree.t(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc """
  Save arbitrary session metadata.

  For app-specific data such as model selection, thinking level, or title.
  Tree structural data (nodes, path, cursors) is handled by `save_tree/3`.

  Accepts a map or a keyword list — keyword input is normalised to a map
  before storage. Merges with any existing metadata by key; partial updates
  are supported. Explicit `nil` values overwrite, so callers can reset a
  field by passing `key: nil`.
  """
  @callback save_metadata(session_id(), metadata() | keyword(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc """
  Load a session. Returns the tree and any saved metadata as a map, or
  `:not_found` when no session exists for the given id.
  """
  @callback load(session_id(), opts :: keyword()) ::
              {:ok, OmniUI.Tree.t(), metadata()} | {:error, :not_found}

  @doc """
  List session summaries, ordered by `updated_at` descending.

  Returns id, title, and timestamps for each session. The title is
  extracted from saved metadata (the `:title` key) if present.

  ## Options

    * `:limit` — maximum number of sessions to return. Unlimited by default.
    * `:offset` — number of sessions to skip from the start. Defaults to 0.

  Callers infer whether more results are available by comparing the
  returned list length to the requested `:limit`.
  """
  @callback list(opts :: keyword()) :: {:ok, [session_info()]}

  @doc """
  Delete a session and all its data.
  """
  @callback delete(session_id(), opts :: keyword()) :: :ok | {:error, term()}

  # ── Public API ─────────────────────────────────────────────────────

  @doc "Save a conversation tree via the configured adapter."
  @spec save_tree(session_id(), OmniUI.Tree.t(), keyword()) :: :ok | {:error, term()}
  def save_tree(session_id, tree, opts \\ []) do
    case adapter(opts) do
      nil -> :ok
      mod -> mod.save_tree(session_id, tree, drop_adapter(opts))
    end
  end

  @doc "Save session metadata via the configured adapter."
  @spec save_metadata(session_id(), metadata() | keyword(), keyword()) :: :ok | {:error, term()}
  def save_metadata(session_id, metadata, opts \\ []) do
    case adapter(opts) do
      nil -> :ok
      mod -> mod.save_metadata(session_id, metadata, drop_adapter(opts))
    end
  end

  @doc "Load a session via the configured adapter."
  @spec load(session_id(), keyword()) ::
          {:ok, OmniUI.Tree.t(), metadata()} | {:error, :not_found}
  def load(session_id, opts \\ []) do
    case adapter(opts) do
      nil -> {:error, :not_found}
      mod -> mod.load(session_id, drop_adapter(opts))
    end
  end

  @doc "List session summaries via the configured adapter."
  @spec list(keyword()) :: {:ok, [session_info()]}
  def list(opts \\ []) do
    case adapter(opts) do
      nil -> {:ok, []}
      mod -> mod.list(drop_adapter(opts))
    end
  end

  @doc "Delete a session via the configured adapter."
  @spec delete(session_id(), keyword()) :: :ok | {:error, term()}
  def delete(session_id, opts \\ []) do
    case adapter(opts) do
      nil -> :ok
      mod -> mod.delete(session_id, drop_adapter(opts))
    end
  end

  @doc "Returns the currently configured adapter (or `nil`)."
  @spec adapter(keyword()) :: adapter() | nil
  def adapter(opts \\ []) do
    Keyword.get_lazy(opts, :adapter, fn ->
      Application.get_env(:omni, __MODULE__, []) |> Keyword.get(:adapter)
    end)
  end

  defp drop_adapter(opts), do: Keyword.delete(opts, :adapter)
end
