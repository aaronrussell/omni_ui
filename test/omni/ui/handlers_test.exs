defmodule Omni.UI.HandlersTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket
  alias Omni.UI.Handlers
  alias Omni.UI.Test.StubSession

  defp build_socket(assigns \\ %{}) do
    %Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns),
      private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}}
    }
  end

  defp init_socket(extra_assigns \\ %{}) do
    socket = Omni.UI.init_session(build_socket(), model: {:anthropic, "claude-haiku-4-5"})
    update_in(socket.assigns, &Map.merge(&1, extra_assigns))
  end

  defp streaming_turn(opts \\ []) do
    content = Keyword.get(opts, :content, [])
    status = Keyword.get(opts, :status, :streaming)

    %Omni.UI.Turn{
      id: Keyword.get(opts, :id),
      status: status,
      content: content,
      user_text: [%Omni.Content.Text{text: "hello"}],
      user_attachments: []
    }
  end

  defp simple_tree do
    %Omni.Session.Tree{}
    |> Omni.Session.Tree.push(Omni.message("Hello"))
    |> Omni.Session.Tree.push(
      Omni.message(role: :assistant, content: [%Omni.Content.Text{text: "Hi there"}]),
      %Omni.Usage{input_tokens: 10, output_tokens: 5, total_tokens: 15}
    )
  end

  # ── handle_session_event: streaming deltas ──────────────────────

  describe "handle_session_event :thinking_start" do
    test "pushes an empty Thinking block onto current_turn" do
      socket = init_socket(%{current_turn: streaming_turn()})
      socket = Handlers.handle_session_event(:thinking_start, %{}, socket)
      assert [%Omni.Content.Thinking{text: ""}] = socket.assigns.current_turn.content
    end
  end

  describe "handle_session_event :text_start" do
    test "pushes an empty Text block onto current_turn" do
      socket = init_socket(%{current_turn: streaming_turn()})
      socket = Handlers.handle_session_event(:text_start, %{}, socket)
      assert [%Omni.Content.Text{text: ""}] = socket.assigns.current_turn.content
    end
  end

  describe "handle_session_event :thinking_delta" do
    test "appends delta to the last content block" do
      turn = streaming_turn(content: [%Omni.Content.Thinking{text: "I think"}])
      socket = init_socket(%{current_turn: turn})

      socket = Handlers.handle_session_event(:thinking_delta, %{delta: " therefore"}, socket)

      assert [%Omni.Content.Thinking{text: "I think therefore"}] =
               socket.assigns.current_turn.content
    end
  end

  describe "handle_session_event :text_delta" do
    test "appends delta to the last content block" do
      turn = streaming_turn(content: [%Omni.Content.Text{text: "Hello"}])
      socket = init_socket(%{current_turn: turn})

      socket = Handlers.handle_session_event(:text_delta, %{delta: " world"}, socket)
      assert [%Omni.Content.Text{text: "Hello world"}] = socket.assigns.current_turn.content
    end
  end

  # ── handle_session_event: tool use ──────────────────────────────

  describe "handle_session_event :tool_use_start" do
    test "pushes a stub ToolUse with id, name, and input" do
      socket = init_socket(%{current_turn: streaming_turn()})

      data = %{id: "tool_1", name: "files", input: %{"path" => "/tmp"}}
      socket = Handlers.handle_session_event(:tool_use_start, data, socket)

      assert [%Omni.Content.ToolUse{id: "tool_1", name: "files", input: %{"path" => "/tmp"}}] =
               socket.assigns.current_turn.content
    end

    test "defaults input to empty map when not provided" do
      socket = init_socket(%{current_turn: streaming_turn()})

      data = %{id: "tool_2", name: "repl"}
      socket = Handlers.handle_session_event(:tool_use_start, data, socket)

      assert [%Omni.Content.ToolUse{id: "tool_2", name: "repl", input: %{}}] =
               socket.assigns.current_turn.content
    end
  end

  describe "handle_session_event :tool_use_end" do
    test "replaces the stub ToolUse with the final struct" do
      stub = %Omni.Content.ToolUse{id: "tool_1", name: "files", input: %{}}
      turn = streaming_turn(content: [stub])
      socket = init_socket(%{current_turn: turn})

      final = %Omni.Content.ToolUse{id: "tool_1", name: "files", input: %{"path" => "/home"}}
      socket = Handlers.handle_session_event(:tool_use_end, %{content: final}, socket)

      assert [^final] = socket.assigns.current_turn.content
    end
  end

  describe "handle_session_event :tool_result" do
    test "stores the tool result keyed by tool_use_id" do
      socket = init_socket(%{current_turn: streaming_turn()})

      result = %Omni.Content.ToolResult{
        tool_use_id: "tool_1",
        name: "files",
        content: [%Omni.Content.Text{text: "ok"}]
      }

      socket = Handlers.handle_session_event(:tool_result, result, socket)
      assert socket.assigns.current_turn.tool_results["tool_1"] == result
    end
  end

  # ── handle_session_event: turn lifecycle ────────────────────────

  describe "handle_session_event :turn" do
    test "nils out current_turn" do
      socket = init_socket(%{current_turn: streaming_turn()})
      socket = Handlers.handle_session_event(:turn, {:stop, %{}}, socket)
      assert socket.assigns.current_turn == nil
    end

    test "nils out current_turn for continue kind" do
      socket = init_socket(%{current_turn: streaming_turn()})
      socket = Handlers.handle_session_event(:turn, {:continue, %{}}, socket)
      assert socket.assigns.current_turn == nil
    end
  end

  describe "handle_session_event :message" do
    test "starts a fresh streaming turn from a user message when no turn in flight" do
      socket = init_socket(%{current_turn: nil})
      message = Omni.message("Follow-up question")
      socket = Handlers.handle_session_event(:message, message, socket)

      turn = socket.assigns.current_turn
      assert turn.status == :streaming
      assert [%Omni.Content.Text{text: "Follow-up question"}] = turn.user_text
    end

    test "ignores the message when a turn is already in flight" do
      existing_turn = streaming_turn()
      socket = init_socket(%{current_turn: existing_turn})
      message = Omni.message("ignored")

      socket = Handlers.handle_session_event(:message, message, socket)
      assert socket.assigns.current_turn == existing_turn
    end

    test "ignores non-user messages" do
      socket = init_socket(%{current_turn: nil})
      message = Omni.message(role: :assistant, content: [%Omni.Content.Text{text: "hi"}])
      socket = Handlers.handle_session_event(:message, message, socket)
      assert socket.assigns.current_turn == nil
    end
  end

  # ── handle_session_event: tree ──────────────────────────────────

  describe "handle_session_event :tree" do
    test "assigns tree and rebuilds turns stream" do
      socket = init_socket()
      tree = simple_tree()

      socket = Handlers.handle_session_event(:tree, %{tree: tree}, socket)

      assert socket.assigns.tree == tree
      assert %Omni.Usage{} = socket.assigns.usage
    end

    test "updates usage from tree" do
      socket = init_socket()
      tree = simple_tree()

      socket = Handlers.handle_session_event(:tree, %{tree: tree}, socket)

      assert socket.assigns.usage.input_tokens == 10
      assert socket.assigns.usage.output_tokens == 5
    end
  end

  # ── handle_session_event: store ─────────────────────────────────

  describe "handle_session_event :store saved" do
    test "patches URL on first save" do
      socket = init_socket(%{session_id: "abc-123", url_synced: false})

      socket = Handlers.handle_session_event(:store, {:saved, :tree}, socket)

      assert socket.redirected == {:live, :patch, %{to: "/?session_id=abc-123", kind: :push}}
      assert socket.assigns.url_synced == true
    end

    test "skips URL patch when already synced" do
      socket = init_socket(%{session_id: "abc-123", url_synced: true})

      socket = Handlers.handle_session_event(:store, {:saved, :tree}, socket)

      assert socket.redirected == nil
    end
  end

  describe "handle_session_event :store error" do
    @tag :capture_log
    test "logs the error and sends a notification" do
      socket = init_socket()

      socket = Handlers.handle_session_event(:store, {:error, :tree, :enoent}, socket)

      assert socket == socket
      assert_received {Omni.UI, :notify, %Omni.UI.Notification{level: :error}}
    end
  end

  # ── handle_session_event: metadata ──────────────────────────────

  describe "handle_session_event :title" do
    test "assigns the new title" do
      socket = init_socket()
      socket = Handlers.handle_session_event(:title, "New Title", socket)
      assert socket.assigns.title == "New Title"
    end
  end

  describe "handle_session_event :state" do
    test "syncs model and thinking from agent state" do
      socket = init_socket()
      {:ok, model} = Omni.get_model(:anthropic, "claude-sonnet-4-5")

      state = %Omni.Agent.State{
        model: model,
        opts: [thinking: :high],
        system: nil,
        tools: []
      }

      socket = Handlers.handle_session_event(:state, state, socket)
      assert socket.assigns.model == model
      assert socket.assigns.thinking == :high
    end

    test "defaults thinking to false when not in opts" do
      socket = init_socket(%{thinking: :high})
      {:ok, model} = Omni.get_model(:anthropic, "claude-haiku-4-5")

      state = %Omni.Agent.State{
        model: model,
        opts: [],
        system: nil,
        tools: []
      }

      socket = Handlers.handle_session_event(:state, state, socket)
      assert socket.assigns.thinking == false
    end
  end

  describe "handle_session_event :status" do
    test "returns socket unchanged" do
      socket = init_socket()
      assert Handlers.handle_session_event(:status, :idle, socket) == socket
    end
  end

  describe "handle_session_event :error" do
    @tag :capture_log
    test "sets current_turn to error status when a turn is in flight" do
      turn = streaming_turn()
      socket = init_socket(%{current_turn: turn})

      socket = Handlers.handle_session_event(:error, "something broke", socket)

      assert socket.assigns.current_turn.status == :error
      assert socket.assigns.current_turn.error == "something broke"
    end

    @tag :capture_log
    test "formats error with message key" do
      turn = streaming_turn()
      socket = init_socket(%{current_turn: turn})

      socket = Handlers.handle_session_event(:error, %{message: "rate limited"}, socket)

      assert socket.assigns.current_turn.error == "rate limited"
    end

    @tag :capture_log
    test "uses fallback message for non-string, non-map errors" do
      turn = streaming_turn()
      socket = init_socket(%{current_turn: turn})

      socket = Handlers.handle_session_event(:error, :timeout, socket)

      assert socket.assigns.current_turn.error == "Something went wrong. Please try again."
    end

    @tag :capture_log
    test "sends notification and returns socket when no turn in flight" do
      socket = init_socket(%{current_turn: nil})

      socket = Handlers.handle_session_event(:error, "oops", socket)

      assert socket.assigns.current_turn == nil
      assert_received {Omni.UI, :notify, %Omni.UI.Notification{level: :error}}
    end
  end

  describe "handle_session_event catch-all" do
    test "returns socket unchanged for unknown events" do
      socket = init_socket()
      assert Handlers.handle_session_event(:unknown_event, %{}, socket) == socket
    end
  end

  # ── handle_info: notifications ──────────────────────────────────

  describe "handle_info :notify" do
    test "inserts notification into stream and tracks its id" do
      socket = init_socket()
      notification = Omni.UI.Notification.new(:info, "Hello")

      assert {:noreply, socket} =
               Handlers.handle_info({Omni.UI, :notify, notification}, socket)

      assert notification.id in socket.assigns.notification_ids
    end

    test "evicts oldest when exceeding cap of 5" do
      socket = init_socket()

      final_socket =
        Enum.reduce(1..6, socket, fn i, acc ->
          n = Omni.UI.Notification.new(:info, "msg #{i}")
          {:noreply, acc} = Handlers.handle_info({Omni.UI, :notify, n}, acc)
          acc
        end)

      assert length(final_socket.assigns.notification_ids) == 5
    end

    test "schedules auto-dismiss via send_after" do
      socket = init_socket()
      notification = Omni.UI.Notification.new(:warning, "temp", timeout: 100)

      {:noreply, _socket} = Handlers.handle_info({Omni.UI, :notify, notification}, socket)

      assert_receive {Omni.UI, :dismiss_notification, id} when id == notification.id, 200
    end
  end

  describe "handle_info :dismiss_notification" do
    test "removes notification id from tracking list" do
      socket = init_socket(%{notification_ids: [1, 2, 3]})

      assert {:noreply, socket} =
               Handlers.handle_info({Omni.UI, :dismiss_notification, 2}, socket)

      assert socket.assigns.notification_ids == [1, 3]
    end

    test "is a no-op for an id that doesn't exist" do
      socket = init_socket(%{notification_ids: [1, 2]})

      assert {:noreply, socket} =
               Handlers.handle_info({Omni.UI, :dismiss_notification, 99}, socket)

      assert socket.assigns.notification_ids == [1, 2]
    end
  end

  # ── handle_event: omni:select ───────────────────────────────────

  describe "handle_event omni:select model" do
    test "updates the model assign" do
      socket = init_socket()

      assert {:noreply, socket} =
               Handlers.handle_event(
                 "omni:select",
                 %{"name" => "model", "value" => "anthropic:claude-sonnet-4-5"},
                 socket
               )

      assert %Omni.Model{id: "claude-sonnet-4-5"} = socket.assigns.model
    end
  end

  describe "handle_event omni:select thinking" do
    test "updates the thinking assign" do
      socket = init_socket()

      assert {:noreply, socket} =
               Handlers.handle_event(
                 "omni:select",
                 %{"name" => "thinking", "value" => "high"},
                 socket
               )

      assert socket.assigns.thinking == :high
    end
  end

  # ── handle_event: omni:dismiss ──────────────────────────────────

  describe "handle_event omni:dismiss" do
    test "delegates to dismiss_notification handler" do
      socket = init_socket(%{notification_ids: [42]})

      assert {:noreply, socket} =
               Handlers.handle_event("omni:dismiss", %{"id" => "42"}, socket)

      assert socket.assigns.notification_ids == []
    end
  end

  # ── handle_event: omni:navigate ─────────────────────────────────

  describe "handle_event omni:navigate" do
    setup do
      {:ok, pid} = StubSession.start_link(navigate: :ok)
      {:ok, session: pid}
    end

    test "pushes omni:updated event on success", %{session: session} do
      socket = init_socket(%{session: session})

      assert {:noreply, socket} =
               Handlers.handle_event("omni:navigate", %{"node_id" => "42"}, socket)

      assert ["omni:updated", %{}] in (socket.private.live_temp[:push_events] || [])
    end

    test "sends notification on :not_found error" do
      {:ok, pid} = StubSession.start_link(navigate: {:error, :not_found})
      socket = init_socket(%{session: pid})

      assert {:noreply, _socket} =
               Handlers.handle_event("omni:navigate", %{"node_id" => "bad"}, socket)

      assert_received {Omni.UI, :notify, %Omni.UI.Notification{level: :warning}}
    end

    test "sends notification on :busy error" do
      {:ok, pid} = StubSession.start_link(navigate: {:error, :busy})
      socket = init_socket(%{session: pid})

      assert {:noreply, _socket} =
               Handlers.handle_event("omni:navigate", %{"node_id" => "42"}, socket)

      assert_received {Omni.UI, :notify, %Omni.UI.Notification{level: :warning, message: msg}}

      assert msg =~ "current turn"
    end
  end

  # ── handle_event: omni:retry ────────────────────────────────────

  describe "handle_event omni:retry" do
    test "no-ops when current_turn is nil" do
      socket = init_socket(%{current_turn: nil})

      assert {:noreply, socket} = Handlers.handle_event("omni:retry", %{}, socket)
      assert socket.assigns.current_turn == nil
    end

    test "no-ops when current_turn is not in error state" do
      turn = streaming_turn(status: :streaming)
      socket = init_socket(%{current_turn: turn})

      assert {:noreply, socket} = Handlers.handle_event("omni:retry", %{}, socket)
      assert socket.assigns.current_turn.status == :streaming
    end

    test "re-prompts and creates a new streaming turn on error" do
      {:ok, pid} = StubSession.start_link(prompt: :ok)

      turn = streaming_turn(status: :error)
      socket = init_socket(%{current_turn: turn, session: pid})

      assert {:noreply, socket} = Handlers.handle_event("omni:retry", %{}, socket)
      assert socket.assigns.current_turn.status == :streaming
    end
  end

  # ── handle_event: omni:regenerate ───────────────────────────────

  describe "handle_event omni:regenerate" do
    test "creates a new streaming turn on success" do
      {:ok, pid} = StubSession.start_link(branch: :ok)

      tree = simple_tree()
      [turn_id | _] = tree.path

      socket = init_socket(%{session: pid, tree: tree})

      assert {:noreply, socket} =
               Handlers.handle_event(
                 "omni:regenerate",
                 %{"turn_id" => turn_id},
                 socket
               )

      assert socket.assigns.current_turn.status == :streaming
    end

    test "sends notification on branch error" do
      {:ok, pid} = StubSession.start_link(branch: {:error, :busy})

      tree = simple_tree()
      socket = init_socket(%{session: pid, tree: tree})

      assert {:noreply, _socket} =
               Handlers.handle_event(
                 "omni:regenerate",
                 %{"turn_id" => List.first(tree.path)},
                 socket
               )

      assert_received {Omni.UI, :notify, %Omni.UI.Notification{level: :warning}}
    end
  end

  # ── handle_info: new_message ────────────────────────────────────

  describe "handle_info :new_message" do
    test "prompts the session and sets a streaming turn" do
      {:ok, pid} = StubSession.start_link(prompt: :ok)
      socket = init_socket(%{session: pid})

      message = Omni.message("Hello agent")

      assert {:noreply, socket} =
               Handlers.handle_info({Omni.UI, :new_message, message}, socket)

      assert socket.assigns.current_turn.status == :streaming
      assert [%Omni.Content.Text{text: "Hello agent"}] = socket.assigns.current_turn.user_text
    end
  end

  # ── handle_info: edit_message ───────────────────────────────────

  describe "handle_info :edit_message" do
    test "branches from the parent node and sets a streaming turn" do
      {:ok, pid} = StubSession.start_link(branch: :ok)

      tree = simple_tree()
      [turn_id | _] = tree.path
      socket = init_socket(%{session: pid, tree: tree})

      message = Omni.message("Edited prompt")

      assert {:noreply, socket} =
               Handlers.handle_info({Omni.UI, :edit_message, turn_id, message}, socket)

      assert socket.assigns.current_turn.status == :streaming
    end

    test "sends notification on branch error" do
      {:ok, pid} = StubSession.start_link(branch: {:error, :paused})

      tree = simple_tree()
      [turn_id | _] = tree.path
      socket = init_socket(%{session: pid, tree: tree})

      message = Omni.message("Edited prompt")

      assert {:noreply, _socket} =
               Handlers.handle_info({Omni.UI, :edit_message, turn_id, message}, socket)

      assert_received {Omni.UI, :notify, %Omni.UI.Notification{level: :warning}}
    end
  end
end
