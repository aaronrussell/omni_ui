defmodule OmniUI.TreeTest do
  use ExUnit.Case, async: true

  alias OmniUI.Tree
  alias Omni.{Message, Usage}

  defp msg(text), do: Message.new(text)
  defp assistant(text), do: Message.new(role: :assistant, content: text)
  defp usage(input, output), do: %Usage{input_tokens: input, output_tokens: output}

  # Builds the example tree from the spec:
  #
  #   1 ── 2 ── 3 ── 4 ── 5 ── 6
  #                   │
  #                   ├── 7 ── 8
  #                   │
  #                   └── 9
  #
  # Messages: 1=r0, 2=a0, 3=r1, 4=a1, 5=r2, 6=a2 (linear)
  # Branch at node 4: 7=r3alt, 8=a3alt
  # Branch at node 4: 9=r3alt2
  # Active path: [1, 2, 3, 4, 7, 8]
  defp example_tree do
    tree = %Tree{}

    # Linear conversation: user, assistant, user, assistant, user, assistant
    {1, tree} = Tree.push_node(tree, msg("r0"))
    {2, tree} = Tree.push_node(tree, assistant("a0"))
    {3, tree} = Tree.push_node(tree, msg("r1"))
    {4, tree} = Tree.push_node(tree, assistant("a1"))
    {5, tree} = Tree.push_node(tree, msg("r2"))
    {6, tree} = Tree.push_node(tree, assistant("a2"))

    # Navigate back to node 4 (assistant a1) and branch
    {:ok, tree} = Tree.navigate(tree, 4)
    {7, tree} = Tree.push_node(tree, msg("r3alt"))
    {8, tree} = Tree.push_node(tree, assistant("a3alt"))

    # Navigate back to node 4 again and branch again
    {:ok, tree} = Tree.navigate(tree, 4)
    {9, tree} = Tree.push_node(tree, msg("r3alt2"))

    # Navigate to node 8 to set active path
    {:ok, tree} = Tree.navigate(tree, 8)

    tree
  end

  describe "push/3" do
    test "returns just the tree (pipe-safe)" do
      tree =
        %Tree{}
        |> Tree.push(msg("a"))
        |> Tree.push(assistant("b"))
        |> Tree.push(msg("c"))

      assert tree.path == [1, 2, 3]
      assert Tree.size(tree) == 3
    end

    test "stores usage when provided" do
      tree =
        %Tree{}
        |> Tree.push(msg("a"))
        |> Tree.push(assistant("b"), usage(10, 20))

      assert tree.nodes[1].usage == nil
      assert tree.nodes[2].usage == %Usage{input_tokens: 10, output_tokens: 20}
    end
  end

  describe "push_node/3" do
    test "push to empty tree creates node 1 with parent nil" do
      {id, tree} = Tree.push_node(%Tree{}, msg("hello"))

      assert id == 1
      assert tree.path == [1]
      assert tree.nodes[1].parent_id == nil
      assert %Message{role: :user} = tree.nodes[1].message
    end

    test "push to non-empty tree sets parent to previous head" do
      {_, tree} = Tree.push_node(%Tree{}, msg("first"))
      {id, tree} = Tree.push_node(tree, msg("second"))

      assert id == 2
      assert tree.nodes[2].parent_id == 1
      assert tree.path == [1, 2]
    end

    test "sequential pushes build a linear chain" do
      tree = %Tree{}
      {1, tree} = Tree.push_node(tree, msg("a"))
      {2, tree} = Tree.push_node(tree, assistant("b"))
      {3, tree} = Tree.push_node(tree, msg("c"))

      assert tree.path == [1, 2, 3]
      assert tree.nodes[1].parent_id == nil
      assert tree.nodes[2].parent_id == 1
      assert tree.nodes[3].parent_id == 2
    end

    test "assigns sequential IDs based on map size" do
      tree = %Tree{}
      {1, tree} = Tree.push_node(tree, msg("a"))
      {2, tree} = Tree.push_node(tree, msg("b"))

      # Navigate back and branch — next ID is 3 (map_size + 1)
      {:ok, tree} = Tree.navigate(tree, 1)
      {3, _tree} = Tree.push_node(tree, msg("c"))
    end

    test "stores usage when provided" do
      {_, tree} = Tree.push_node(%Tree{}, msg("hello"))
      {id, tree} = Tree.push_node(tree, assistant("response"), usage(100, 50))

      assert tree.nodes[1].usage == nil
      assert tree.nodes[id].usage == %Usage{input_tokens: 100, output_tokens: 50}
    end
  end

  describe "navigate/2" do
    test "navigate to existing node sets active path" do
      tree = %Tree{}
      {1, tree} = Tree.push_node(tree, msg("a"))
      {2, tree} = Tree.push_node(tree, msg("b"))
      {3, tree} = Tree.push_node(tree, msg("c"))

      {:ok, tree} = Tree.navigate(tree, 2)

      assert tree.path == [1, 2]
      assert Tree.head(tree) == 2
    end

    test "navigate to root node" do
      tree = %Tree{}
      {1, tree} = Tree.push_node(tree, msg("a"))
      {_, tree} = Tree.push_node(tree, msg("b"))

      {:ok, tree} = Tree.navigate(tree, 1)

      assert tree.path == [1]
    end

    test "navigate to non-existent node returns error" do
      assert {:error, :not_found} = Tree.navigate(%Tree{}, 99)
    end

    test "navigate then push creates a branch" do
      tree = %Tree{}
      {1, tree} = Tree.push_node(tree, msg("a"))
      {2, tree} = Tree.push_node(tree, msg("b"))

      {:ok, tree} = Tree.navigate(tree, 1)
      {3, tree} = Tree.push_node(tree, msg("c"))

      # Node 3 branches from node 1
      assert tree.nodes[3].parent_id == 1
      assert tree.path == [1, 3]

      # Both node 2 and node 3 are children of node 1
      assert MapSet.new(Tree.children(tree, 1)) == MapSet.new([2, 3])
    end
  end

  describe "clear/1" do
    test "clears active path but preserves nodes" do
      tree = %Tree{}
      {_, tree} = Tree.push_node(tree, msg("a"))
      {_, tree} = Tree.push_node(tree, msg("b"))

      tree = Tree.clear(tree)

      assert tree.path == []
      assert map_size(tree.nodes) == 2
    end

    test "push after clear creates a new root" do
      tree = %Tree{}
      {_, tree} = Tree.push_node(tree, msg("a"))

      tree = Tree.clear(tree)
      {2, tree} = Tree.push_node(tree, msg("b"))

      assert tree.nodes[2].parent_id == nil
      assert tree.path == [2]
    end

    test "clearing an already empty path is idempotent" do
      tree = Tree.clear(%Tree{})

      assert tree.path == []
      assert tree.nodes == %{}
    end
  end

  describe "messages/1" do
    test "returns list of messages along active path" do
      tree = %Tree{}
      {_, tree} = Tree.push_node(tree, msg("a"))
      {_, tree} = Tree.push_node(tree, assistant("r1"))
      {_, tree} = Tree.push_node(tree, msg("b"))

      messages = Tree.messages(tree)

      assert length(messages) == 3
      assert [%{role: :user}, %{role: :assistant}, %{role: :user}] = messages
    end

    test "returns empty list for empty tree" do
      assert Tree.messages(%Tree{}) == []
    end

    test "returns empty list after clear" do
      tree = %Tree{}
      {_, tree} = Tree.push_node(tree, msg("a"))

      tree = Tree.clear(tree)

      assert Tree.messages(tree) == []
    end

    test "reflects active branch only" do
      tree = example_tree()
      messages = Tree.messages(tree)

      texts = Enum.map(messages, fn m -> hd(m.content).text end)

      # Active path is [1, 2, 3, 4, 7, 8] — should see r0, a0, r1, a1, r3alt, a3alt
      assert texts == ["r0", "a0", "r1", "a1", "r3alt", "a3alt"]
    end
  end

  describe "usage/1" do
    test "returns zero usage for empty tree" do
      assert Tree.usage(%Tree{}) == %Usage{}
    end

    test "accumulates usage across all nodes" do
      tree =
        %Tree{}
        |> Tree.push(msg("a"))
        |> Tree.push(assistant("b"), usage(100, 50))
        |> Tree.push(msg("c"))
        |> Tree.push(assistant("d"), usage(200, 80))

      result = Tree.usage(tree)
      assert result.input_tokens == 300
      assert result.output_tokens == 130
    end

    test "skips nodes with nil usage" do
      tree =
        %Tree{}
        |> Tree.push(msg("a"))
        |> Tree.push(assistant("b"), usage(10, 20))

      assert Tree.usage(tree) == %Usage{input_tokens: 10, output_tokens: 20}
    end

    test "includes usage from all branches" do
      tree =
        %Tree{}
        |> Tree.push(msg("a"))
        |> Tree.push(assistant("b"), usage(10, 20))

      {:ok, tree} = Tree.navigate(tree, 1)
      tree = Tree.push(tree, assistant("c"), usage(30, 40))

      result = Tree.usage(tree)
      assert result.input_tokens == 40
      assert result.output_tokens == 60
    end
  end

  describe "size/1" do
    test "returns size of tree" do
      tree = %Tree{}
      {_, tree} = Tree.push_node(tree, msg("a"))
      {_, tree} = Tree.push_node(tree, msg("b"))

      assert Tree.size(tree) == 2
    end

    test "returns 0 for empty tree" do
      assert Tree.size(%Tree{}) == 0
    end

    test "counts all nodes across branches" do
      tree = example_tree()
      assert Tree.size(tree) == 9
    end
  end

  describe "head/1" do
    test "returns last node ID in active path" do
      tree = %Tree{}
      {_, tree} = Tree.push_node(tree, msg("a"))
      {_, tree} = Tree.push_node(tree, msg("b"))

      assert Tree.head(tree) == 2
    end

    test "returns nil for empty tree" do
      assert Tree.head(%Tree{}) == nil
    end
  end

  describe "get_message/2" do
    test "returns message for existing ID" do
      {_, tree} = Tree.push_node(%Tree{}, msg("hello"))

      message = Tree.get_message(tree, 1)

      assert %Message{role: :user} = message
    end

    test "returns nil for non-existent ID" do
      assert Tree.get_message(%Tree{}, 99) == nil
    end
  end

  describe "get_node/2" do
    test "returns full tree node for existing ID" do
      {_, tree} = Tree.push_node(%Tree{}, msg("hello"))

      node = Tree.get_node(tree, 1)

      assert node.id == 1
      assert node.parent_id == nil
      assert %Message{role: :user} = node.message
      assert node.usage == nil
    end

    test "returns nil for non-existent ID" do
      assert Tree.get_node(%Tree{}, 99) == nil
    end
  end

  describe "children/2" do
    test "returns child node IDs" do
      tree = example_tree()

      # Node 4 (assistant a1) has children 5, 7, 9
      children = Tree.children(tree, 4)
      assert children == [5, 7, 9]
    end

    test "returns empty list for leaf node" do
      tree = example_tree()

      assert Tree.children(tree, 6) == []
      assert Tree.children(tree, 8) == []
      assert Tree.children(tree, 9) == []
    end

    test "returns single child for non-branch node" do
      tree = example_tree()

      assert Tree.children(tree, 1) == [2]
      assert Tree.children(tree, 7) == [8]
    end
  end

  describe "siblings/2" do
    test "returns sibling node IDs excluding self" do
      tree = example_tree()

      # Nodes 5, 7, 9 are all children of node 4
      assert Tree.siblings(tree, 5) == [7, 9]
      assert Tree.siblings(tree, 7) == [5, 9]
      assert Tree.siblings(tree, 9) == [5, 7]
    end

    test "returns empty list when no siblings" do
      tree = example_tree()

      assert Tree.siblings(tree, 1) == []
      assert Tree.siblings(tree, 2) == []
      assert Tree.siblings(tree, 8) == []
    end

    test "handles root-level siblings" do
      tree = %Tree{}
      {1, tree} = Tree.push_node(tree, msg("a"))

      tree = Tree.clear(tree)
      {2, tree} = Tree.push_node(tree, msg("b"))

      tree = Tree.clear(tree)
      {3, tree} = Tree.push_node(tree, msg("c"))

      assert Tree.siblings(tree, 1) == [2, 3]
      assert Tree.siblings(tree, 2) == [1, 3]
      assert Tree.siblings(tree, 3) == [1, 2]
    end

    test "returns empty list for non-existent node" do
      assert Tree.siblings(%Tree{}, 99) == []
    end
  end

  describe "path_to/2" do
    test "returns root-first path for existing node" do
      tree = example_tree()

      assert {:ok, [1, 2, 3, 4, 7, 8]} = Tree.path_to(tree, 8)
      assert {:ok, [1, 2, 3, 4, 5, 6]} = Tree.path_to(tree, 6)
      assert {:ok, [1, 2, 3, 4, 9]} = Tree.path_to(tree, 9)
    end

    test "returns error for non-existent node" do
      assert {:error, :not_found} = Tree.path_to(%Tree{}, 99)
    end

    test "path to root node is just the root" do
      tree = example_tree()

      assert {:ok, [1]} = Tree.path_to(tree, 1)
    end
  end

  describe "roots/1" do
    test "returns single root for normal tree" do
      tree = example_tree()

      assert Tree.roots(tree) == [1]
    end

    test "returns multiple roots after clear + push cycles" do
      tree = %Tree{}
      {1, tree} = Tree.push_node(tree, msg("a"))

      tree = Tree.clear(tree)
      {2, tree} = Tree.push_node(tree, msg("b"))

      tree = Tree.clear(tree)
      {3, tree} = Tree.push_node(tree, msg("c"))

      assert Tree.roots(tree) == [1, 2, 3]
    end

    test "returns empty list for empty tree" do
      assert Tree.roots(%Tree{}) == []
    end
  end

  describe "Enumerable" do
    test "Enum.map yields tree nodes for active path" do
      tree = example_tree()

      result = Enum.map(tree, fn %{id: id} -> id end)

      assert result == [1, 2, 3, 4, 7, 8]
    end

    test "Enum.count returns active path length" do
      tree = example_tree()

      assert Enum.count(tree) == 6
    end

    test "Enum.to_list on empty tree returns empty list" do
      assert Enum.to_list(%Tree{}) == []
    end

    test "iteration yields tree nodes with message data" do
      tree = %Tree{}
      {_, tree} = Tree.push_node(tree, msg("hello"))

      [node] = Enum.to_list(tree)

      assert %{id: 1, parent_id: nil, message: %Message{role: :user}, usage: nil} = node
    end

    test "iterates only the active path" do
      tree = example_tree()

      # Active path is [1, 2, 3, 4, 7, 8] — should not see nodes 5, 6, 9
      ids = Enum.map(tree, fn %{id: id} -> id end)
      assert ids == [1, 2, 3, 4, 7, 8]
      refute 5 in ids
      refute 6 in ids
      refute 9 in ids
    end
  end

  describe "integration: example tree" do
    test "full tree structure matches spec" do
      tree = example_tree()

      # 9 nodes total
      assert map_size(tree.nodes) == 9

      # Active path is [1, 2, 3, 4, 7, 8]
      assert tree.path == [1, 2, 3, 4, 7, 8]

      # Parent pointers
      assert tree.nodes[1].parent_id == nil
      assert tree.nodes[2].parent_id == 1
      assert tree.nodes[3].parent_id == 2
      assert tree.nodes[4].parent_id == 3
      assert tree.nodes[5].parent_id == 4
      assert tree.nodes[6].parent_id == 5
      assert tree.nodes[7].parent_id == 4
      assert tree.nodes[8].parent_id == 7
      assert tree.nodes[9].parent_id == 4
    end

    test "navigate to node 6 shows that branch" do
      tree = example_tree()

      {:ok, tree} = Tree.navigate(tree, 6)

      assert tree.path == [1, 2, 3, 4, 5, 6]
      assert Tree.head(tree) == 6

      texts =
        tree
        |> Tree.messages()
        |> Enum.map(fn m -> hd(m.content).text end)

      assert texts == ["r0", "a0", "r1", "a1", "r2", "a2"]
    end

    test "navigate back to node 8 restores original path" do
      tree = example_tree()

      {:ok, tree} = Tree.navigate(tree, 6)
      {:ok, tree} = Tree.navigate(tree, 8)

      assert tree.path == [1, 2, 3, 4, 7, 8]
    end
  end
end
