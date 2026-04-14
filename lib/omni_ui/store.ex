defmodule OmniUI.Store do
  @moduledoc """
  Behaviour for session persistence backends.

  Defines the contract for saving and loading conversation trees and
  session metadata. OmniUI ships a filesystem adapter for development
  (`OmniUI.Store.FileSystem`); consumers implement their own for Ecto,
  Redis, or other backends.

  ## Callbacks

  All callbacks accept `opts :: keyword()` as an extension point for
  scoping, pagination, and adapter-specific options.

  ## Scoping

  Multi-tenant applications pass `scope: value` in opts to isolate
  sessions by user, organization, or other tenant key:

      save_tree(session_id, tree, scope: current_user.id)
      load(session_id, scope: current_user.id)
      list(scope: current_user.id)

  Adapters that don't need scoping ignore the option.

  ## Timestamps

  `created_at` and `updated_at` are managed by the adapter, not the
  caller. The adapter sets `created_at` on first save and `updated_at`
  on every save.
  """

  @type session_id :: String.t()
  @type metadata :: %{optional(atom()) => term()}

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
end
