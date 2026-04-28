defmodule OmniUI.Handlers do
  @moduledoc false

  import Phoenix.LiveView
  import Phoenix.Component

  require Logger

  alias Omni.Session.Tree

  @notification_cap 5

  # ── Events ───────────────────────────────────────────────────────

  def handle_event("omni:select_model", %{"value" => value}, socket) do
    [provider, model_id] = String.split(value, ":", parts: 2)
    socket = OmniUI.update_session(socket, model: {String.to_existing_atom(provider), model_id})
    {:noreply, socket}
  end

  def handle_event("omni:select_thinking", %{"value" => value}, socket) do
    thinking = String.to_existing_atom(value)
    socket = OmniUI.update_session(socket, thinking: thinking)
    {:noreply, socket}
  end

  def handle_event("omni:dismiss_notification", %{"id" => id}, socket) do
    handle_info({OmniUI, :dismiss_notification, String.to_integer(id)}, socket)
  end

  # Branching ops are temporarily disabled while the codebase is migrated to
  # `Omni.Session`. The new home for these is `Omni.Session.navigate/2` and
  # `Omni.Session.branch/2,3`. Re-enable the handler bodies (and their
  # accompanying tests) when re-wiring branching against the session API.
  #
  # def handle_event("omni:navigate", %{"node_id" => node_id}, socket) do
  #   {:ok, tree} = OmniUI.Tree.navigate(socket.assigns.tree, node_id)
  #   tree = OmniUI.Tree.extend(tree)
  #   turns = OmniUI.Turn.all(tree)
  #
  #   socket =
  #     socket
  #     |> assign(tree: tree)
  #     |> stream(:turns, turns, reset: true)
  #     |> push_event("omni:updated", %{})
  #
  #   {:noreply, socket}
  # end
  #
  # def handle_event("omni:regenerate", %{"turn_id" => turn_id}, socket) do
  #   turn = OmniUI.Turn.get(socket.assigns.tree, turn_id)
  #   {:ok, tree} = OmniUI.Tree.navigate(socket.assigns.tree, turn_id)
  #   messages = OmniUI.Tree.messages(tree) |> Enum.drop(-1)
  #
  #   :ok =
  #     Omni.Agent.set_state(socket.assigns.agent, :context, fn ctx ->
  #       Map.put(ctx, :messages, messages)
  #     end)
  #
  #   turns = OmniUI.Turn.all(tree) |> Enum.drop(-1)
  #
  #   current_turn = %OmniUI.Turn{
  #     id: turn_id,
  #     status: :streaming,
  #     user_text: turn.user_text,
  #     user_attachments: turn.user_attachments,
  #     user_timestamp: turn.user_timestamp
  #   }
  #
  #   content = turn.user_text ++ turn.user_attachments
  #   :ok = Omni.Agent.prompt(socket.assigns.agent, content)
  #
  #   socket =
  #     socket
  #     |> assign(tree: tree, current_turn: current_turn)
  #     |> stream(:turns, turns, reset: true)
  #     |> push_event("omni:updated", %{})
  #
  #   {:noreply, socket}
  # end

  # ── Messages ─────────────────────────────────────────────────────

  def handle_info({OmniUI, :new_message, message}, socket) do
    :ok = Omni.Session.prompt(socket.assigns.session, message.content)

    current_turn = %OmniUI.Turn{
      id: nil,
      status: :streaming,
      user_text: Enum.filter(message.content, &match?(%Omni.Content.Text{}, &1)),
      user_attachments: Enum.filter(message.content, &match?(%Omni.Content.Attachment{}, &1)),
      user_timestamp: message.timestamp
    }

    {:noreply, assign(socket, current_turn: current_turn)}
  end

  # Editing a user message is a tree-mutating branch op. Disabled during the
  # session migration; re-enable against `Omni.Session.branch/3` when wiring
  # branching back in.
  #
  # def handle_info({OmniUI, :edit_message, turn_id, message}, socket) do
  #   %{parent_id: parent_id} = socket.assigns.tree.nodes[turn_id]
  #   {:ok, tree} = OmniUI.Tree.navigate(socket.assigns.tree, parent_id)
  #   {id, tree} = OmniUI.Tree.push_node(tree, message)
  #   messages = OmniUI.Tree.messages(tree) |> Enum.drop(-1)
  #
  #   :ok =
  #     Omni.Agent.set_state(socket.assigns.agent, :context, fn ctx ->
  #       Map.put(ctx, :messages, messages)
  #     end)
  #
  #   :ok = Omni.Agent.prompt(socket.assigns.agent, message.content)
  #
  #   turns = OmniUI.Turn.all(tree) |> Enum.drop(-1)
  #
  #   current_turn = %OmniUI.Turn{
  #     id: id,
  #     status: :streaming,
  #     user_text: Enum.filter(message.content, &match?(%Omni.Content.Text{}, &1)),
  #     user_attachments: Enum.filter(message.content, &match?(%Omni.Content.Attachment{}, &1)),
  #     user_timestamp: message.timestamp
  #   }
  #
  #   socket =
  #     socket
  #     |> assign(tree: tree, current_turn: current_turn)
  #     |> stream(:turns, turns, reset: true)
  #     |> push_event("omni:updated", %{})
  #
  #   {:noreply, socket}
  # end
  def handle_info({OmniUI, :edit_message, _turn_id, _message}, socket) do
    OmniUI.notify(:info, "Editing messages is temporarily disabled.")
    {:noreply, socket}
  end

  # ── Notifications ────────────────────────────────────────────────

  def handle_info({OmniUI, :notify, notification}, socket) do
    Process.send_after(
      self(),
      {OmniUI, :dismiss_notification, notification.id},
      notification.timeout
    )

    ids = socket.assigns.notification_ids ++ [notification.id]
    {evicted, kept} = split_evicted(ids)

    socket =
      Enum.reduce(evicted, socket, fn id, s ->
        stream_delete(s, :notifications, %{id: id})
      end)

    {:noreply,
     socket
     |> stream_insert(:notifications, notification, at: 0)
     |> assign(:notification_ids, kept)}
  end

  def handle_info({OmniUI, :dismiss_notification, id}, socket) do
    {:noreply,
     socket
     |> stream_delete(:notifications, %{id: id})
     |> update(:notification_ids, &List.delete(&1, id))}
  end

  defp split_evicted(ids) when length(ids) > @notification_cap do
    Enum.split(ids, length(ids) - @notification_cap)
  end

  defp split_evicted(ids), do: {[], ids}

  # ── Session events (return socket, not {:noreply, socket}) ───────

  # Streaming-deltas accumulate into @current_turn.

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

  # Turn boundary. Session forwards this from the inner agent. On {:stop, _}
  # the streaming turn is over — drop @current_turn so subsequent renders
  # show the committed turn from the :tree event that follows. On
  # {:continue, _} keep @current_turn so streaming carries on across the
  # continuation step.
  def handle_agent_event(:turn, {:stop, _response}, socket) do
    assign(socket, :current_turn, nil)
  end

  def handle_agent_event(:turn, {:continue, _response}, socket), do: socket

  # Tree mirror. Session emits this after every tree mutation (turn commit,
  # navigate, branch). new_nodes is non-empty only on a turn commit.
  def handle_agent_event(:tree, %{tree: tree, new_nodes: new_nodes}, socket) do
    socket = assign(socket, tree: tree, usage: Tree.usage(tree))

    case new_nodes do
      [] ->
        socket

      [first_id | _] ->
        # The first new node id is the user message that started this turn
        # (`Turn.get/2` walks forward to the next non-tool-result user
        # boundary, so a multi-step turn collapses correctly).
        case OmniUI.Turn.get(tree, first_id) do
          nil -> socket
          turn -> stream_insert(socket, :turns, turn)
        end
    end
  end

  # Persistence acks. The first save after starting a fresh session is the
  # signal that the session id is real — patch the URL so the user can
  # bookmark/share/reload.
  def handle_agent_event(:store, {:saved, _kind}, socket) do
    if socket.assigns[:url_synced] do
      socket
    else
      socket
      |> push_patch(to: "/?session_id=#{socket.assigns.session_id}")
      |> assign(:url_synced, true)
    end
  end

  def handle_agent_event(:store, {:error, kind, reason}, socket) do
    Logger.error("Session store error (#{kind}): #{inspect(reason)}")
    OmniUI.notify(:error, "Couldn't save your changes.")
    socket
  end

  # Title changes (set via Omni.Session.set_title/2). Mirror to assigns; the
  # consumer can render @title if it surfaces a title bar.
  def handle_agent_event(:title, title, socket) do
    assign(socket, :title, title)
  end

  # Best-effort sync if the session's agent state changes underneath us
  # (e.g. via a future Manager). The explicit update_session/2 paths already
  # keep model/thinking aligned, so this is defensive.
  def handle_agent_event(:state, %_{model: model, opts: opts}, socket) do
    thinking = Keyword.get(opts, :thinking, false)

    socket
    |> assign(:model, model)
    |> assign(:thinking, thinking)
  end

  def handle_agent_event(:status, _status, socket), do: socket

  def handle_agent_event(:error, reason, socket) do
    Logger.error("Session error: #{inspect(reason)}")

    OmniUI.notify(:error, "Something went wrong")

    case socket.assigns.current_turn do
      nil ->
        socket

      turn ->
        socket
        |> assign(:current_turn, nil)
        |> stream_insert(:turns, %{turn | status: :error})
    end
  end

  # Catch-all for unhandled session events
  def handle_agent_event(_event, _data, socket), do: socket
end
