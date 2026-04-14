defmodule OmniUI.Handlers do
  @moduledoc false

  import Phoenix.LiveView
  import Phoenix.Component

  require Logger

  # ── Events ───────────────────────────────────────────────────────

  def handle_event("omni:select_model", %{"value" => value}, socket) do
    [provider, model_id] = String.split(value, ":", parts: 2)
    socket = OmniUI.update_agent(socket, model: {String.to_existing_atom(provider), model_id})
    {:noreply, OmniUI.fire_ui_event(socket, :model_changed, socket.assigns.model)}
  end

  def handle_event("omni:select_thinking", %{"value" => value}, socket) do
    thinking = String.to_existing_atom(value)
    socket = OmniUI.update_agent(socket, thinking: thinking)
    {:noreply, OmniUI.fire_ui_event(socket, :thinking_changed, thinking)}
  end

  def handle_event("omni:navigate", %{"node_id" => node_id}, socket) do
    {:ok, tree} = OmniUI.Tree.navigate(socket.assigns.tree, node_id)
    tree = OmniUI.Tree.extend(tree)
    turns = OmniUI.Turn.all(tree)

    socket =
      socket
      |> assign(tree: tree)
      |> stream(:turns, turns, reset: true)
      |> push_event("omni:updated", %{})

    {:noreply, OmniUI.fire_ui_event(socket, :navigated, node_id)}
  end

  def handle_event("omni:regenerate", %{"turn_id" => turn_id}, socket) do
    turn = OmniUI.Turn.get(socket.assigns.tree, turn_id)

    # Navigate tree so head = user message node (new response branches from here)
    {:ok, tree} = OmniUI.Tree.navigate(socket.assigns.tree, turn_id)

    # Sync agent context to messages BEFORE the user message
    # (Agent.prompt will re-add the user message)
    messages = OmniUI.Tree.messages(tree) |> Enum.drop(-1)

    :ok =
      Omni.Agent.set_state(socket.assigns.agent, :context, fn ctx ->
        Map.put(ctx, :messages, messages)
      end)

    # Reset stream with all turns except the one being regenerated
    turns = OmniUI.Turn.all(tree) |> Enum.drop(-1)

    # Build current_turn from original user message data
    current_turn = %OmniUI.Turn{
      id: turn_id,
      status: :streaming,
      user_text: turn.user_text,
      user_attachments: turn.user_attachments,
      user_timestamp: turn.user_timestamp
    }

    # Prompt agent with original user content
    content = turn.user_text ++ turn.user_attachments
    :ok = Omni.Agent.prompt(socket.assigns.agent, content)

    socket =
      socket
      |> assign(tree: tree, current_turn: current_turn)
      |> stream(:turns, turns, reset: true)
      |> push_event("omni:updated", %{})

    {:noreply, socket}
  end

  # ── Messages ─────────────────────────────────────────────────────

  def handle_info({OmniUI, :new_message, message}, socket) do
    {id, tree} = OmniUI.Tree.push_node(socket.assigns.tree, message)
    :ok = Omni.Agent.prompt(socket.assigns.agent, message.content)

    current_turn = %OmniUI.Turn{
      id: id,
      status: :streaming,
      user_text: Enum.filter(message.content, &match?(%Omni.Content.Text{}, &1)),
      user_attachments: Enum.filter(message.content, &match?(%Omni.Content.Attachment{}, &1)),
      user_timestamp: message.timestamp
    }

    socket = assign(socket, tree: tree, current_turn: current_turn)

    {:noreply, OmniUI.fire_ui_event(socket, :message_sent, {id, message})}
  end

  def handle_info({OmniUI, :edit_message, turn_id, message}, socket) do
    # Navigate to the PARENT of the edited message so push_node creates a sibling.
    %{parent_id: parent_id} = socket.assigns.tree.nodes[turn_id]
    {:ok, tree} = OmniUI.Tree.navigate(socket.assigns.tree, parent_id)

    # Push new user message (branches from parent as sibling of original)
    {id, tree} = OmniUI.Tree.push_node(tree, message)

    # Sync agent context to messages BEFORE the new user message
    messages = OmniUI.Tree.messages(tree) |> Enum.drop(-1)

    :ok =
      Omni.Agent.set_state(socket.assigns.agent, :context, fn ctx ->
        Map.put(ctx, :messages, messages)
      end)

    # Prompt agent with new content
    :ok = Omni.Agent.prompt(socket.assigns.agent, message.content)

    # Reset stream with all turns before the edited one
    turns = OmniUI.Turn.all(tree) |> Enum.drop(-1)

    current_turn = %OmniUI.Turn{
      id: id,
      status: :streaming,
      user_text: Enum.filter(message.content, &match?(%Omni.Content.Text{}, &1)),
      user_attachments: Enum.filter(message.content, &match?(%Omni.Content.Attachment{}, &1)),
      user_timestamp: message.timestamp
    }

    socket =
      socket
      |> assign(tree: tree, current_turn: current_turn)
      |> stream(:turns, turns, reset: true)
      |> push_event("omni:updated", %{})

    {:noreply, OmniUI.fire_ui_event(socket, :message_edited, {id, message})}
  end

  # ── Agent events (return socket, not {:noreply, socket}) ─────────

  @doc false
  def handle_agent_event(:thinking_start, _data, socket) do
    update(socket, :current_turn, fn turn ->
      OmniUI.Turn.push_content(turn, %Omni.Content.Thinking{text: ""})
    end)
  end

  def handle_agent_event(:text_start, _data, socket) do
    update(socket, :current_turn, fn turn ->
      OmniUI.Turn.push_content(turn, %Omni.Content.Text{text: ""})
    end)
  end

  def handle_agent_event(delta_type, %{delta: delta}, socket)
      when delta_type in [:thinking_delta, :text_delta] do
    update(socket, :current_turn, fn turn ->
      OmniUI.Turn.push_delta(turn, delta)
    end)
  end

  def handle_agent_event(:tool_use_end, %{content: tool_use}, socket) do
    update(socket, :current_turn, fn turn ->
      OmniUI.Turn.push_content(turn, tool_use)
    end)
  end

  def handle_agent_event(:tool_result, tool_result, socket) do
    update(socket, :current_turn, fn turn ->
      OmniUI.Turn.put_tool_result(turn, tool_result)
    end)
  end

  def handle_agent_event(:stop, response, socket) do
    [_user_msg | rest_msgs] = response.messages
    {[res_id | _], tree} = tree_push_all(socket.assigns.tree, rest_msgs, response.usage)

    user_node_id = socket.assigns.current_turn.id
    parent_id = tree.nodes[user_node_id].parent_id
    edits = OmniUI.Tree.children(tree, parent_id)
    regens = OmniUI.Tree.children(tree, user_node_id)

    turn = OmniUI.Turn.new(user_node_id, response.messages, response.usage)
    turn = %{turn | res_id: res_id, edits: edits, regens: regens}

    socket
    |> assign(current_turn: nil, tree: tree)
    |> update(:usage, &Omni.Usage.add(&1, response.usage))
    |> stream_insert(:turns, turn)
  end

  def handle_agent_event(:error, reason, socket) do
    Logger.error("Agent error: #{inspect(reason)}")

    turn = Map.put(socket.assigns.current_turn, :status, :error)

    socket
    |> assign(current_turn: nil)
    |> stream_insert(:turns, turn)
    |> put_flash(:error, "Something went wrong")
  end

  # Catch-all for unhandled agent events
  def handle_agent_event(_event, _data, socket), do: socket

  # ── Helpers ──────────────────────────────────────────────────────

  defp tree_push_all(tree, messages, usage, node_ids \\ [])

  defp tree_push_all(tree, [last], usage, node_ids) do
    {id, tree} = OmniUI.Tree.push_node(tree, last, usage)
    {Enum.reverse([id | node_ids]), tree}
  end

  defp tree_push_all(tree, [message | rest], usage, node_ids) do
    {id, tree} = OmniUI.Tree.push_node(tree, message)
    tree_push_all(tree, rest, usage, [id | node_ids])
  end
end
