defmodule OmniUI.Store.FileSystemTest do
  use ExUnit.Case, async: true

  alias OmniUI.Store.FileSystem
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

  defp read_meta_json(ctx, session_id) do
    Path.join([ctx.tmp_dir, session_id, "meta.json"])
    |> File.read!()
    |> JSON.decode!()
  end

  defp read_tree_jsonl(ctx, session_id) do
    Path.join([ctx.tmp_dir, session_id, "tree.jsonl"])
    |> File.read!()
    |> String.split("\n", trim: true)
  end

  describe "save_tree + load round-trip" do
    test "saves and loads a simple tree", ctx do
      tree = sample_tree()

      assert :ok = FileSystem.save_tree("sess_1", tree, opts(ctx))
      assert {:ok, loaded, %{}} = FileSystem.load("sess_1", opts(ctx))

      assert loaded == tree
    end

    test "saves and loads a branching tree", ctx do
      tree = branching_tree()

      assert :ok = FileSystem.save_tree("sess_1", tree, opts(ctx))
      assert {:ok, loaded, %{}} = FileSystem.load("sess_1", opts(ctx))

      assert loaded == tree
      assert Tree.messages(loaded) == Tree.messages(tree)
    end

    test "preserves cursors and path", ctx do
      tree = branching_tree()

      :ok = FileSystem.save_tree("sess_1", tree, opts(ctx))
      {:ok, loaded, _} = FileSystem.load("sess_1", opts(ctx))

      assert loaded.cursors == tree.cursors
      assert loaded.path == tree.path
    end

    test "preserves usage records on message nodes", ctx do
      tree = sample_tree()
      :ok = FileSystem.save_tree("sess_1", tree, opts(ctx))

      {:ok, loaded, _} = FileSystem.load("sess_1", opts(ctx))
      assistant_node = Enum.find(loaded.nodes |> Map.values(), &(&1.message.role == :assistant))
      assert %Usage{input_tokens: 10, output_tokens: 20} = assistant_node.usage
    end
  end

  describe "incremental save via :new_node_ids" do
    test "appends only listed nodes to tree.jsonl", ctx do
      tree = sample_tree()
      :ok = FileSystem.save_tree("sess_1", tree, opts(ctx))

      assert length(read_tree_jsonl(ctx, "sess_1")) == 2

      extended = Tree.push(tree, msg("follow-up"))
      new_id = List.last(extended.path)

      :ok = FileSystem.save_tree("sess_1", extended, opts(ctx, new_node_ids: [new_id]))

      lines = read_tree_jsonl(ctx, "sess_1")
      assert length(lines) == 3

      {:ok, loaded, _} = FileSystem.load("sess_1", opts(ctx))
      assert loaded == extended
    end

    test "full rewrite when :new_node_ids is absent", ctx do
      tree = sample_tree()
      :ok = FileSystem.save_tree("sess_1", tree, opts(ctx))

      # Save again without :new_node_ids — same node count, not doubled
      :ok = FileSystem.save_tree("sess_1", tree, opts(ctx))

      assert length(read_tree_jsonl(ctx, "sess_1")) == 2
    end

    test "incremental save still refreshes meta (path, cursors, updated_at)", ctx do
      tree = branching_tree()
      :ok = FileSystem.save_tree("sess_1", tree, opts(ctx))

      meta1 = read_meta_json(ctx, "sess_1")

      Process.sleep(10)
      {:ok, navigated} = Tree.navigate(tree, 4)
      :ok = FileSystem.save_tree("sess_1", navigated, opts(ctx, new_node_ids: []))

      meta2 = read_meta_json(ctx, "sess_1")
      assert meta2["path"] != meta1["path"]
      assert meta2["updated_at"] != meta1["updated_at"]
    end
  end

  describe "meta.json file shape" do
    test "title is lifted to top level for readable inspection", ctx do
      :ok = FileSystem.save_tree("sess_1", sample_tree(), opts(ctx))
      :ok = FileSystem.save_metadata("sess_1", [title: "Readable Title"], opts(ctx))

      meta = read_meta_json(ctx, "sess_1")
      assert meta["title"] == "Readable Title"
    end

    test "timestamps are ISO8601 strings", ctx do
      :ok = FileSystem.save_tree("sess_1", sample_tree(), opts(ctx))

      meta = read_meta_json(ctx, "sess_1")
      assert {:ok, %DateTime{}, _} = DateTime.from_iso8601(meta["created_at"])
      assert {:ok, %DateTime{}, _} = DateTime.from_iso8601(meta["updated_at"])
    end

    test "path and cursors are stored as plain JSON values", ctx do
      :ok = FileSystem.save_tree("sess_1", branching_tree(), opts(ctx))

      meta = read_meta_json(ctx, "sess_1")
      assert is_list(meta["path"])
      assert Enum.all?(meta["path"], &is_integer/1)
      assert is_list(meta["cursors"])
      assert Enum.all?(meta["cursors"], &match?([_, _], &1))
    end

    test "metadata bag is an ETF wrapper", ctx do
      :ok = FileSystem.save_tree("sess_1", sample_tree(), opts(ctx))
      :ok = FileSystem.save_metadata("sess_1", [model: {:anthropic, "claude"}], opts(ctx))

      meta = read_meta_json(ctx, "sess_1")
      assert %{"__etf" => blob} = meta["metadata"]
      assert is_binary(blob)
    end

    test "title is lifted to top level, not duplicated inside the ETF blob", ctx do
      :ok = FileSystem.save_metadata("sess_1", [title: "Lifted", model: :x], opts(ctx))

      meta = read_meta_json(ctx, "sess_1")
      assert meta["title"] == "Lifted"

      {:ok, blob} = Base.decode64(meta["metadata"]["__etf"])
      decoded = :erlang.binary_to_term(blob)
      refute Map.has_key?(decoded, :title)
      assert decoded == %{model: :x}
    end

    test "title absent from saved metadata means no top-level title field", ctx do
      :ok = FileSystem.save_metadata("sess_1", [model: :x], opts(ctx))

      meta = read_meta_json(ctx, "sess_1")
      refute Map.has_key?(meta, "title")
    end
  end

  describe "metadata round-trip preserves Elixir term fidelity" do
    test "atoms, tuples, and nested structures survive", ctx do
      :ok = FileSystem.save_tree("sess_1", sample_tree(), opts(ctx))

      metadata = %{
        model: {:anthropic, "claude-sonnet-4-20250514"},
        thinking: :high,
        nested: %{key: :value, list: [:a, :b, {:c, 1}]}
      }

      :ok = FileSystem.save_metadata("sess_1", metadata, opts(ctx))

      {:ok, _tree, loaded} = FileSystem.load("sess_1", opts(ctx))
      assert loaded == metadata
    end

    test "accepts keyword list input and returns a map", ctx do
      :ok =
        FileSystem.save_metadata(
          "sess_1",
          [model: {:anthropic, "claude"}, thinking: :high],
          opts(ctx)
        )

      {:ok, _tree, loaded} = FileSystem.load("sess_1", opts(ctx))
      assert loaded == %{model: {:anthropic, "claude"}, thinking: :high}
    end

    test "save_metadata without prior tree creates meta.json and load returns an empty tree",
         ctx do
      :ok = FileSystem.save_metadata("sess_1", [title: "Test"], opts(ctx))

      assert {:ok, %Tree{nodes: nodes}, metadata} = FileSystem.load("sess_1", opts(ctx))
      assert nodes == %{}
      assert metadata == %{title: "Test"}
      assert File.exists?(Path.join([ctx.tmp_dir, "sess_1", "meta.json"]))
    end

    test "load returns :not_found only when neither tree nor meta exists", ctx do
      assert {:error, :not_found} = FileSystem.load("no_such_session", opts(ctx))
    end

    test "save_metadata merges rather than overwrites", ctx do
      :ok = FileSystem.save_metadata("sess_1", [model: :old_model, thinking: false], opts(ctx))
      :ok = FileSystem.save_metadata("sess_1", [title: "New title"], opts(ctx))

      assert {:ok, _tree, metadata} = FileSystem.load("sess_1", opts(ctx))
      assert metadata[:model] == :old_model
      assert metadata[:thinking] == false
      assert metadata[:title] == "New title"
    end

    test "save_metadata with explicit nil overwrites the value", ctx do
      :ok = FileSystem.save_metadata("sess_1", [title: "Old"], opts(ctx))
      :ok = FileSystem.save_metadata("sess_1", [title: nil], opts(ctx))

      assert {:ok, _tree, metadata} = FileSystem.load("sess_1", opts(ctx))
      assert metadata[:title] == nil
      assert Map.has_key?(metadata, :title)
    end
  end

  describe "save_tree preserves metadata" do
    test "subsequent save_tree does not overwrite metadata", ctx do
      tree = sample_tree()
      :ok = FileSystem.save_tree("sess_1", tree, opts(ctx))

      metadata = %{model: {:anthropic, "claude-sonnet-4-20250514"}, thinking: :high}
      :ok = FileSystem.save_metadata("sess_1", metadata, opts(ctx))

      updated_tree = Tree.push(tree, msg("another"))
      :ok = FileSystem.save_tree("sess_1", updated_tree, opts(ctx))

      {:ok, loaded_tree, loaded_meta} = FileSystem.load("sess_1", opts(ctx))
      assert loaded_tree == updated_tree
      assert loaded_meta == metadata
    end
  end

  describe "timestamps" do
    test "created_at set on first save, updated_at advances", ctx do
      tree = sample_tree()
      :ok = FileSystem.save_tree("sess_1", tree, opts(ctx))

      meta1 = read_meta_json(ctx, "sess_1")
      {:ok, created1, _} = DateTime.from_iso8601(meta1["created_at"])
      {:ok, updated1, _} = DateTime.from_iso8601(meta1["updated_at"])

      assert created1 == updated1

      Process.sleep(10)
      :ok = FileSystem.save_tree("sess_1", tree, opts(ctx))

      meta2 = read_meta_json(ctx, "sess_1")
      {:ok, created2, _} = DateTime.from_iso8601(meta2["created_at"])
      {:ok, updated2, _} = DateTime.from_iso8601(meta2["updated_at"])

      assert created2 == created1
      assert DateTime.compare(updated2, updated1) == :gt
    end
  end

  describe "list" do
    test "lists multiple sessions", ctx do
      :ok = FileSystem.save_tree("sess_1", sample_tree(), opts(ctx))
      :ok = FileSystem.save_tree("sess_2", sample_tree(), opts(ctx))

      {:ok, sessions} = FileSystem.list(opts(ctx))

      assert length(sessions) == 2
      ids = Enum.map(sessions, & &1.id)
      assert "sess_1" in ids
      assert "sess_2" in ids
    end

    test "returns empty list when no sessions exist", ctx do
      assert {:ok, []} = FileSystem.list(opts(ctx))
    end

    test "sorted by updated_at descending", ctx do
      :ok = FileSystem.save_tree("older", sample_tree(), opts(ctx))
      Process.sleep(10)
      :ok = FileSystem.save_tree("newer", sample_tree(), opts(ctx))

      {:ok, sessions} = FileSystem.list(opts(ctx))

      assert [%{id: "newer"}, %{id: "older"}] = sessions
    end

    test "includes title from metadata without decoding the ETF bag", ctx do
      :ok = FileSystem.save_tree("sess_1", sample_tree(), opts(ctx))
      :ok = FileSystem.save_metadata("sess_1", [title: "My Chat"], opts(ctx))

      {:ok, [session]} = FileSystem.list(opts(ctx))
      assert session.title == "My Chat"
    end

    test "title is nil when not in metadata", ctx do
      :ok = FileSystem.save_tree("sess_1", sample_tree(), opts(ctx))

      {:ok, [session]} = FileSystem.list(opts(ctx))
      assert session.title == nil
    end

    test "honours :limit", ctx do
      for i <- 1..5 do
        :ok = FileSystem.save_tree("sess_#{i}", sample_tree(), opts(ctx))
        Process.sleep(5)
      end

      {:ok, sessions} = FileSystem.list(opts(ctx, limit: 2))
      assert length(sessions) == 2
    end

    test "honours :offset", ctx do
      for i <- 1..4 do
        :ok = FileSystem.save_tree("sess_#{i}", sample_tree(), opts(ctx))
        Process.sleep(5)
      end

      {:ok, all} = FileSystem.list(opts(ctx))
      {:ok, skipped} = FileSystem.list(opts(ctx, offset: 2))

      assert length(skipped) == 2
      assert Enum.map(skipped, & &1.id) == Enum.map(Enum.drop(all, 2), & &1.id)
    end

    test ":limit and :offset together paginate through the full set", ctx do
      for i <- 1..5 do
        :ok = FileSystem.save_tree("sess_#{i}", sample_tree(), opts(ctx))
        Process.sleep(5)
      end

      {:ok, page1} = FileSystem.list(opts(ctx, limit: 2, offset: 0))
      {:ok, page2} = FileSystem.list(opts(ctx, limit: 2, offset: 2))
      {:ok, page3} = FileSystem.list(opts(ctx, limit: 2, offset: 4))

      assert length(page1) == 2
      assert length(page2) == 2
      assert length(page3) == 1

      ids = Enum.map(page1 ++ page2 ++ page3, & &1.id)
      assert length(Enum.uniq(ids)) == 5
    end
  end

  describe "delete" do
    test "deletes a session", ctx do
      :ok = FileSystem.save_tree("sess_1", sample_tree(), opts(ctx))
      assert {:ok, _, _} = FileSystem.load("sess_1", opts(ctx))

      assert :ok = FileSystem.delete("sess_1", opts(ctx))
      assert {:error, :not_found} = FileSystem.load("sess_1", opts(ctx))
    end

    test "deleting non-existent session returns :ok", ctx do
      assert :ok = FileSystem.delete("nonexistent", opts(ctx))
    end
  end

  describe "load errors" do
    test "returns error for non-existent session", ctx do
      assert {:error, :not_found} = FileSystem.load("nonexistent", opts(ctx))
    end
  end

  describe "scoping" do
    test "scoped sessions are isolated", ctx do
      tree = sample_tree()

      :ok = FileSystem.save_tree("sess_1", tree, opts(ctx, scope: "user_1"))
      :ok = FileSystem.save_tree("sess_1", tree, opts(ctx, scope: "user_2"))

      {:ok, user1} = FileSystem.list(opts(ctx, scope: "user_1"))
      {:ok, user2} = FileSystem.list(opts(ctx, scope: "user_2"))

      assert length(user1) == 1
      assert length(user2) == 1
    end

    test "scoped and unscoped sessions don't mix", ctx do
      tree = sample_tree()

      :ok = FileSystem.save_tree("unscoped", tree, opts(ctx))
      :ok = FileSystem.save_tree("scoped", tree, opts(ctx, scope: "user_1"))

      {:ok, unscoped} = FileSystem.list(opts(ctx))
      {:ok, scoped} = FileSystem.list(opts(ctx, scope: "user_1"))

      unscoped_ids = Enum.map(unscoped, & &1.id)
      scoped_ids = Enum.map(scoped, & &1.id)

      assert "unscoped" in unscoped_ids
      refute "scoped" in unscoped_ids
      assert "scoped" in scoped_ids
      refute "unscoped" in scoped_ids
    end

    test "scoped load works", ctx do
      tree = sample_tree()
      :ok = FileSystem.save_tree("sess_1", tree, opts(ctx, scope: "user_1"))

      assert {:ok, loaded, %{}} = FileSystem.load("sess_1", opts(ctx, scope: "user_1"))
      assert loaded == tree

      assert {:error, :not_found} = FileSystem.load("sess_1", opts(ctx, scope: "user_2"))
    end

    test "scoped delete only deletes in that scope", ctx do
      tree = sample_tree()
      :ok = FileSystem.save_tree("sess_1", tree, opts(ctx, scope: "user_1"))
      :ok = FileSystem.save_tree("sess_1", tree, opts(ctx, scope: "user_2"))

      :ok = FileSystem.delete("sess_1", opts(ctx, scope: "user_1"))

      assert {:error, :not_found} = FileSystem.load("sess_1", opts(ctx, scope: "user_1"))
      assert {:ok, _, _} = FileSystem.load("sess_1", opts(ctx, scope: "user_2"))
    end
  end
end
