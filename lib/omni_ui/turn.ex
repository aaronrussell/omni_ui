defmodule OmniUI.Turn do
  @moduledoc """
  A UI-oriented view of a conversation exchange.

  Each turn collapses a sequence of tree nodes — a user prompt, any intermediate
  tool-use rounds, and the final assistant response — into a single renderable
  struct. `all/1` walks the active path and chunks it into turns; `get/2`
  returns a single turn by its starting node ID; `new/3` builds a turn from
  raw messages (used during streaming).

  Branching metadata:

    * `edits` — sorted node IDs of sibling user messages sharing the same parent.
      Length > 1 means the user edited their prompt at this point. `id` identifies
      the active edit.
    * `regens` — sorted node IDs of sibling assistant messages sharing the same
      parent user message. Length > 1 means the user regenerated the response.
      `res_id` identifies the active generation.
  """

  alias OmniUI.Tree

  defstruct [
    :id,
    :res_id,
    status: :complete,
    edits: [],
    regens: [],
    user_text: [],
    user_attachments: [],
    user_timestamp: nil,
    content: [],
    timestamp: nil,
    tool_results: %{},
    error: nil,
    usage: %Omni.Usage{}
  ]

  @type t :: %__MODULE__{
          id: Tree.node_id(),
          res_id: Tree.node_id() | nil,
          status: :complete | :streaming | :error,
          edits: [Tree.node_id()],
          regens: [Tree.node_id()],
          user_text: [Omni.Content.Text.t()],
          user_attachments: [Omni.Content.Attachment.t()],
          user_timestamp: DateTime.t() | nil,
          content: [Omni.Message.content()],
          timestamp: DateTime.t() | nil,
          tool_results: %{String.t() => Omni.Content.ToolResult.t()},
          error: String.t() | nil,
          usage: Omni.Usage.t()
        }

  @doc """
  Builds a turn from a node ID, a list of messages, and cumulative usage.

  The first message must be the user prompt. Subsequent messages are reduced
  into the turn: assistant messages append to `content`, and user messages
  containing tool results are collected into `tool_results`.
  """
  @spec new(Tree.node_id(), [Omni.Message.t()], Omni.Usage.t()) :: t()
  def new(node_id, [user | rest], %Omni.Usage{} = usage) do
    turn = %__MODULE__{
      id: node_id,
      user_text: Enum.filter(user.content, &match?(%Omni.Content.Text{}, &1)),
      user_attachments: Enum.filter(user.content, &match?(%Omni.Content.Attachment{}, &1)),
      user_timestamp: user.timestamp,
      usage: usage
    }

    Enum.reduce(rest, turn, &reduce_content/2)
  end

  @doc """
  Converts a tree's active path into a list of turns.

  Chunks the path at user-message boundaries (skipping tool-result user messages),
  then builds a turn from each chunk with edits and regens populated from the
  full tree structure.
  """
  @spec all(Tree.t()) :: [t()]
  def all(%Tree{} = tree) do
    children_map = children_map(tree)

    tree
    |> Enum.chunk_while([], &tree_chunk/2, &after_tree_chunk/1)
    |> Enum.map(&from_tree_nodes(&1, children_map))
  end

  @doc """
  Returns a single turn from the tree starting at the given node ID.

  Walks the active path forward from `node_id`, collecting nodes until the
  next turn boundary (a non-tool-result user message), then builds a turn
  with branching metadata from the full tree structure.
  """
  @spec get(Tree.t(), Tree.node_id()) :: t()
  def get(%Tree{} = tree, node_id) do
    [first | rest] =
      tree.path
      |> Enum.drop_while(&(&1 != node_id))
      |> Enum.map(&tree.nodes[&1])

    turn_nodes =
      Enum.take_while(rest, fn node ->
        not turn_boundary?(node.message)
      end)

    from_tree_nodes([first | turn_nodes], children_map(tree))
  end

  @doc "Appends a content block to the turn's assistant content."
  @spec push_content(t(), Omni.Message.content()) :: t()
  def push_content(%__MODULE__{} = turn, content_block) do
    %{turn | content: turn.content ++ [content_block]}
  end

  @doc "Appends a text delta to the last content block (used during streaming)."
  @spec push_delta(t(), String.t()) :: t()
  def push_delta(%__MODULE__{} = turn, delta) do
    content = List.update_at(turn.content, -1, &%{&1 | text: &1.text <> delta})
    %{turn | content: content}
  end

  @doc "Stores a tool result, keyed by its `tool_use_id`."
  @spec put_tool_result(t(), Omni.Content.ToolResult.t()) :: t()
  def put_tool_result(%__MODULE__{} = turn, tool_result) do
    tool_results = Map.put(turn.tool_results, tool_result.tool_use_id, tool_result)
    %{turn | tool_results: tool_results}
  end

  @doc "Returns the concatenated text content for the given role in a turn."
  @spec get_text(t(), :user | :assistant) :: String.t()
  def get_text(%__MODULE__{user_text: texts}, :user) do
    texts |> Enum.map(& &1.text) |> Enum.join("\n\n")
  end

  def get_text(%__MODULE__{content: content}, :assistant) do
    content
    |> Enum.filter(&match?(%Omni.Content.Text{}, &1))
    |> Enum.map(& &1.text)
    |> Enum.join("\n\n")
  end

  # Private

  defp from_tree_nodes([%{id: node_id, parent_id: parent_id} | rest] = nodes, children_map) do
    usage =
      rest
      |> Enum.filter(&match?(%Omni.Usage{}, &1.usage))
      |> Enum.reduce(%Omni.Usage{}, &Omni.Usage.add(&2, &1.usage))

    res_id =
      case rest do
        [%{id: id} | _] -> id
        [] -> nil
      end

    edits = Map.get(children_map, parent_id, [])
    regens = Map.get(children_map, node_id, [])

    turn = new(node_id, Enum.map(nodes, & &1.message), usage)
    %{turn | res_id: res_id, edits: edits, regens: regens}
  end

  defp children_map(%Tree{nodes: nodes}) do
    nodes
    |> Enum.reduce(%{}, fn {id, node}, acc ->
      Map.update(acc, node.parent_id, [id], &[id | &1])
    end)
    |> Map.new(fn {k, v} -> {k, Enum.sort(v)} end)
  end

  defp reduce_content(%Omni.Message{role: :user} = msg, turn) do
    tool_results =
      msg.content
      |> Enum.filter(&match?(%Omni.Content.ToolResult{}, &1))
      |> Enum.reduce(turn.tool_results, &Map.put(&2, &1.tool_use_id, &1))

    %{turn | tool_results: tool_results}
  end

  defp reduce_content(%Omni.Message{role: :assistant} = msg, turn) do
    %{turn | content: turn.content ++ msg.content, timestamp: msg.timestamp}
  end

  defp turn_boundary?(%Omni.Message{role: :user, content: content}) do
    not Enum.any?(content, &match?(%Omni.Content.ToolResult{}, &1))
  end

  defp turn_boundary?(_message), do: false

  defp tree_chunk(%{message: %{role: :assistant}}, []), do: {:cont, []}

  defp tree_chunk(node, acc) do
    if turn_boundary?(node.message) and acc != [] do
      {:cont, Enum.reverse(acc), [node]}
    else
      {:cont, [node | acc]}
    end
  end

  defp after_tree_chunk([]), do: {:cont, []}
  defp after_tree_chunk(acc), do: {:cont, Enum.reverse(acc), []}
end
