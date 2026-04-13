defmodule OmniUI.Store.FilesystemTest do
  use ExUnit.Case, async: true

  alias OmniUI.Store.Filesystem
  alias OmniUI.Tree
  alias Omni.{Message, Usage}

  @moduletag :tmp_dir

  defp msg(text), do: Message.new(text)
  defp assistant(text), do: Message.new(role: :assistant, content: text)

  defp opts(%{tmp_dir: tmp_dir}), do: [base_path: tmp_dir]
  defp opts(%{tmp_dir: tmp_dir}, extra), do: Keyword.merge([base_path: tmp_dir], extra)

  defp sample_tree do
    %Tree{}
    |> Tree.push(msg("hello"))
    |> Tree.push(assistant("world"), %Usage{input_tokens: 10, output_tokens: 20})
  end

  defp branching_tree do
    tree = %Tree{}
    {1, tree} = Tree.push_node(tree, msg("r0"))
    {2, tree} = Tree.push_node(tree, assistant("a0"))
    {3, tree} = Tree.push_node(tree, msg("r1"))
    {4, tree} = Tree.push_node(tree, assistant("a1"))

    {:ok, tree} = Tree.navigate(tree, 2)
    {5, tree} = Tree.push_node(tree, msg("r1alt"))
    {_6, tree} = Tree.push_node(tree, assistant("a1alt"))

    tree
  end

  describe "save_tree + load round-trip" do
    test "saves and loads a simple tree", ctx do
      tree = sample_tree()

      assert :ok = Filesystem.save_tree("sess_1", tree, opts(ctx))
      assert {:ok, loaded, []} = Filesystem.load("sess_1", opts(ctx))

      assert loaded == tree
    end

    test "saves and loads a branching tree", ctx do
      tree = branching_tree()

      assert :ok = Filesystem.save_tree("sess_1", tree, opts(ctx))
      assert {:ok, loaded, []} = Filesystem.load("sess_1", opts(ctx))

      assert loaded == tree
      assert Tree.messages(loaded) == Tree.messages(tree)
    end

    test "preserves cursors and path", ctx do
      tree = branching_tree()

      :ok = Filesystem.save_tree("sess_1", tree, opts(ctx))
      {:ok, loaded, _} = Filesystem.load("sess_1", opts(ctx))

      assert loaded.cursors == tree.cursors
      assert loaded.path == tree.path
    end
  end

  describe "save_metadata + load" do
    test "saves and loads metadata", ctx do
      tree = sample_tree()
      :ok = Filesystem.save_tree("sess_1", tree, opts(ctx))

      metadata = [model: {:anthropic, "claude-sonnet-4-20250514"}, thinking: :high]
      :ok = Filesystem.save_metadata("sess_1", metadata, opts(ctx))

      {:ok, _tree, loaded_meta} = Filesystem.load("sess_1", opts(ctx))
      assert loaded_meta == metadata
    end

    test "save_metadata without prior tree creates meta.etf and load returns an empty tree",
         ctx do
      :ok = Filesystem.save_metadata("sess_1", [title: "Test"], opts(ctx))

      assert {:ok, %Tree{nodes: nodes}, metadata} = Filesystem.load("sess_1", opts(ctx))
      assert nodes == %{}
      assert metadata == [title: "Test"]
      assert File.exists?(Path.join([ctx.tmp_dir, "sess_1", "meta.etf"]))
    end

    test "load returns :not_found only when neither tree nor meta exists", ctx do
      assert {:error, :not_found} = Filesystem.load("no_such_session", opts(ctx))
    end

    test "save_metadata merges rather than overwrites", ctx do
      :ok = Filesystem.save_metadata("sess_1", [model: :old_model, thinking: false], opts(ctx))
      :ok = Filesystem.save_metadata("sess_1", [title: "New title"], opts(ctx))

      assert {:ok, _tree, metadata} = Filesystem.load("sess_1", opts(ctx))
      assert metadata[:model] == :old_model
      assert metadata[:thinking] == false
      assert metadata[:title] == "New title"
    end

    test "save_metadata with explicit nil overwrites the value", ctx do
      :ok = Filesystem.save_metadata("sess_1", [title: "Old"], opts(ctx))
      :ok = Filesystem.save_metadata("sess_1", [title: nil], opts(ctx))

      assert {:ok, _tree, metadata} = Filesystem.load("sess_1", opts(ctx))
      assert metadata[:title] == nil
      assert Keyword.has_key?(metadata, :title)
    end
  end

  describe "save_tree preserves metadata" do
    test "subsequent save_tree does not overwrite metadata", ctx do
      tree = sample_tree()
      :ok = Filesystem.save_tree("sess_1", tree, opts(ctx))

      metadata = [model: {:anthropic, "claude-sonnet-4-20250514"}, thinking: :high]
      :ok = Filesystem.save_metadata("sess_1", metadata, opts(ctx))

      # Save tree again (simulates next turn completing)
      updated_tree = Tree.push(tree, msg("another"))
      :ok = Filesystem.save_tree("sess_1", updated_tree, opts(ctx))

      {:ok, loaded_tree, loaded_meta} = Filesystem.load("sess_1", opts(ctx))
      assert loaded_tree == updated_tree
      assert loaded_meta == metadata
    end
  end

  describe "timestamps" do
    test "created_at set on first save, updated_at advances", ctx do
      tree = sample_tree()
      :ok = Filesystem.save_tree("sess_1", tree, opts(ctx))

      meta_path = Path.join([ctx.tmp_dir, "sess_1", "meta.etf"])
      meta1 = meta_path |> File.read!() |> :erlang.binary_to_term()

      assert %DateTime{} = meta1.created_at
      assert meta1.created_at == meta1.updated_at

      Process.sleep(10)
      :ok = Filesystem.save_tree("sess_1", tree, opts(ctx))

      meta2 = meta_path |> File.read!() |> :erlang.binary_to_term()
      assert meta2.created_at == meta1.created_at
      assert DateTime.compare(meta2.updated_at, meta1.updated_at) == :gt
    end
  end

  describe "list" do
    test "lists multiple sessions", ctx do
      :ok = Filesystem.save_tree("sess_1", sample_tree(), opts(ctx))
      :ok = Filesystem.save_tree("sess_2", sample_tree(), opts(ctx))

      {:ok, sessions} = Filesystem.list(opts(ctx))

      assert length(sessions) == 2
      ids = Enum.map(sessions, & &1.id)
      assert "sess_1" in ids
      assert "sess_2" in ids
    end

    test "returns empty list when no sessions exist", ctx do
      assert {:ok, []} = Filesystem.list(opts(ctx))
    end

    test "sorted by updated_at descending", ctx do
      :ok = Filesystem.save_tree("older", sample_tree(), opts(ctx))
      Process.sleep(10)
      :ok = Filesystem.save_tree("newer", sample_tree(), opts(ctx))

      {:ok, sessions} = Filesystem.list(opts(ctx))

      assert [%{id: "newer"}, %{id: "older"}] = sessions
    end

    test "includes title from metadata", ctx do
      :ok = Filesystem.save_tree("sess_1", sample_tree(), opts(ctx))
      :ok = Filesystem.save_metadata("sess_1", [title: "My Chat"], opts(ctx))

      {:ok, [session]} = Filesystem.list(opts(ctx))
      assert session.title == "My Chat"
    end

    test "title is nil when not in metadata", ctx do
      :ok = Filesystem.save_tree("sess_1", sample_tree(), opts(ctx))

      {:ok, [session]} = Filesystem.list(opts(ctx))
      assert session.title == nil
    end
  end

  describe "delete" do
    test "deletes a session", ctx do
      :ok = Filesystem.save_tree("sess_1", sample_tree(), opts(ctx))
      assert {:ok, _, _} = Filesystem.load("sess_1", opts(ctx))

      assert :ok = Filesystem.delete("sess_1", opts(ctx))
      assert {:error, :not_found} = Filesystem.load("sess_1", opts(ctx))
    end

    test "deleting non-existent session returns :ok", ctx do
      assert :ok = Filesystem.delete("nonexistent", opts(ctx))
    end
  end

  describe "load errors" do
    test "returns error for non-existent session", ctx do
      assert {:error, :not_found} = Filesystem.load("nonexistent", opts(ctx))
    end
  end

  describe "scoping" do
    test "scoped sessions are isolated", ctx do
      tree = sample_tree()

      :ok = Filesystem.save_tree("sess_1", tree, opts(ctx, scope: "user_1"))
      :ok = Filesystem.save_tree("sess_1", tree, opts(ctx, scope: "user_2"))

      {:ok, user1} = Filesystem.list(opts(ctx, scope: "user_1"))
      {:ok, user2} = Filesystem.list(opts(ctx, scope: "user_2"))

      assert length(user1) == 1
      assert length(user2) == 1
    end

    test "scoped and unscoped sessions don't mix", ctx do
      tree = sample_tree()

      :ok = Filesystem.save_tree("unscoped", tree, opts(ctx))
      :ok = Filesystem.save_tree("scoped", tree, opts(ctx, scope: "user_1"))

      {:ok, unscoped} = Filesystem.list(opts(ctx))
      {:ok, scoped} = Filesystem.list(opts(ctx, scope: "user_1"))

      unscoped_ids = Enum.map(unscoped, & &1.id)
      scoped_ids = Enum.map(scoped, & &1.id)

      assert "unscoped" in unscoped_ids
      refute "scoped" in unscoped_ids
      assert "scoped" in scoped_ids
      refute "unscoped" in scoped_ids
    end

    test "scoped load works", ctx do
      tree = sample_tree()
      :ok = Filesystem.save_tree("sess_1", tree, opts(ctx, scope: "user_1"))

      assert {:ok, loaded, []} = Filesystem.load("sess_1", opts(ctx, scope: "user_1"))
      assert loaded == tree

      assert {:error, :not_found} = Filesystem.load("sess_1", opts(ctx, scope: "user_2"))
    end

    test "scoped delete only deletes in that scope", ctx do
      tree = sample_tree()
      :ok = Filesystem.save_tree("sess_1", tree, opts(ctx, scope: "user_1"))
      :ok = Filesystem.save_tree("sess_1", tree, opts(ctx, scope: "user_2"))

      :ok = Filesystem.delete("sess_1", opts(ctx, scope: "user_1"))

      assert {:error, :not_found} = Filesystem.load("sess_1", opts(ctx, scope: "user_1"))
      assert {:ok, _, _} = Filesystem.load("sess_1", opts(ctx, scope: "user_2"))
    end
  end
end
