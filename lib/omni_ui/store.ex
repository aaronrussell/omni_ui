defmodule OmniUI.Store do
  @moduledoc """
  Behaviour for session persistence backends.

  Defines the contract for saving and loading conversation trees and
  session metadata. OmniUI ships a filesystem adapter for development
  (`OmniUI.Store.Filesystem`); consumers implement their own for Ecto,
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
  @type metadata :: keyword()

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
  The adapter stores whatever keyword pairs the caller provides and returns
  them verbatim on load.
  """
  @callback save_metadata(session_id(), metadata(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc """
  Load a session. Returns the restored tree and any saved metadata.

  Timestamps are internal to the adapter and not returned here.
  """
  @callback load(session_id(), opts :: keyword()) ::
              {:ok, OmniUI.Tree.t(), metadata()} | {:error, :not_found}

  @doc """
  List session summaries.

  Returns id, title, and timestamps for each session. The title is
  extracted from saved metadata (the `:title` key) if present.
  """
  @callback list(opts :: keyword()) :: {:ok, [session_info()]}

  @doc """
  Delete a session and all its data.
  """
  @callback delete(session_id(), opts :: keyword()) :: :ok | {:error, term()}
end
