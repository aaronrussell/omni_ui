defmodule Omni.UI.Handlers do
  @moduledoc false

  import Phoenix.LiveView
  import Phoenix.Component

  require Logger

  alias Omni.Session.Tree

  @notification_cap 5

  # ── Events ───────────────────────────────────────────────────────

  def handle_event("omni:select_model", %{"value" => value}, socket) do
    [provider, model_id] = String.split(value, ":", parts: 2)
    socket = Omni.UI.update_session(socket, model: {String.to_existing_atom(provider), model_id})
    {:noreply, socket}
  end

  def handle_event("omni:select_thinking", %{"value" => value}, socket) do
    thinking = String.to_existing_atom(value)
    socket = Omni.UI.update_session(socket, thinking: thinking)
    {:noreply, socket}
  end

  def handle_event("omni:dismiss_notification", %{"id" => id}, socket) do
    handle_info({Omni.UI, :dismiss_notification, String.to_integer(id)}, socket)
  end

  def handle_event("omni:navigate", %{"node_id" => node_id}, socket) do
    case Omni.Session.navigate(socket.assigns.session, node_id) do
      :ok ->
        {:noreply, push_event(socket, "omni:updated", %{})}

      {:error, reason} ->
        notify_branch_error(reason)
        {:noreply, socket}
    end
  end

  def handle_event("omni:retry", _params, socket) do
    turn = socket.assigns.current_turn

    if turn && turn.status == :error do
      content = turn.user_text ++ turn.user_attachments
      :ok = Omni.Session.prompt(socket.assigns.session, content)
      message = Omni.message(role: :user, content: content)

      {:noreply,
       socket
       |> assign(:current_turn, streaming_turn(nil, message))
       |> push_event("omni:updated", %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("omni:regenerate", %{"turn_id" => turn_id}, socket) do
    case Omni.Session.branch(socket.assigns.session, turn_id) do
      :ok ->
        message = socket.assigns.tree.nodes[turn_id].message

        {:noreply,
         socket
         |> assign(:current_turn, streaming_turn(turn_id, message))
         |> push_event("omni:updated", %{})}

      {:error, reason} ->
        notify_branch_error(reason)
        {:noreply, socket}
    end
  end

  # ── Messages ─────────────────────────────────────────────────────

  def handle_info({Omni.UI, :new_message, message}, socket) do
    socket = Omni.UI.ensure_session(socket)
    :ok = Omni.Session.prompt(socket.assigns.session, message.content)
    {:noreply, assign(socket, :current_turn, streaming_turn(nil, message))}
  end

  # Editing a user message branches from its parent. Per `Omni.Session.branch/3`
  # semantics, the target is the assistant above the edited user (or `nil` for
  # a root user, which creates a new disjoint root). The new user + assistant
  # turn appends as children — opposite asymmetry from the old tree-owned-state
  # model, which navigated to the user's parent and pushed a sibling user.
  def handle_info({Omni.UI, :edit_message, turn_id, message}, socket) do
    parent_id = socket.assigns.tree.nodes[turn_id].parent_id

    case Omni.Session.branch(socket.assigns.session, parent_id, message.content) do
      :ok ->
        {:noreply,
         socket
         |> assign(:current_turn, streaming_turn(nil, message))
         |> push_event("omni:updated", %{})}

      {:error, reason} ->
        notify_branch_error(reason)
        {:noreply, socket}
    end
  end

  # ── Notifications ────────────────────────────────────────────────

  def handle_info({Omni.UI, :notify, notification}, socket) do
    Process.send_after(
      self(),
      {Omni.UI, :dismiss_notification, notification.id},
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

  def handle_info({Omni.UI, :dismiss_notification, id}, socket) do
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
  def handle_session_event(:thinking_start, _data, socket) do
    update(socket, :current_turn, fn turn ->
      Omni.UI.Turn.push_content(turn, %Omni.Content.Thinking{text: ""})
    end)
  end

  def handle_session_event(:text_start, _data, socket) do
    update(socket, :current_turn, fn turn ->
      Omni.UI.Turn.push_content(turn, %Omni.Content.Text{text: ""})
    end)
  end

  def handle_session_event(delta_type, %{delta: delta}, socket)
      when delta_type in [:thinking_delta, :text_delta] do
    update(socket, :current_turn, fn turn ->
      Omni.UI.Turn.push_delta(turn, delta)
    end)
  end

  # Push a stub ToolUse on start so the header (icon, tool name) renders
  # immediately. The fully-formed struct replaces it on :tool_use_end.
  def handle_session_event(:tool_use_start, %{id: id, name: name} = data, socket) do
    stub = %Omni.Content.ToolUse{id: id, name: name, input: Map.get(data, :input, %{})}

    update(socket, :current_turn, fn turn ->
      Omni.UI.Turn.push_content(turn, stub)
    end)
  end

  def handle_session_event(:tool_use_end, %{content: tool_use}, socket) do
    update(socket, :current_turn, fn turn ->
      Omni.UI.Turn.replace_content(turn, tool_use)
    end)
  end

  def handle_session_event(:tool_result, tool_result, socket) do
    update(socket, :current_turn, fn turn ->
      Omni.UI.Turn.put_tool_result(turn, tool_result)
    end)
  end

  # Turn boundary. Nil out @current_turn so the committed turn appears
  # in the :turns stream via the :tree event that follows. For
  # continuations, a subsequent :message event sets up a fresh
  # @current_turn for the new turn the agent kicks off.
  def handle_session_event(:turn, {_kind, _response}, socket) do
    assign(socket, :current_turn, nil)
  end

  # Continuation user message. The agent emits :message for the new user
  # prompt after :turn {:continue} commits. When no turn is in flight,
  # start a fresh streaming turn from this message.
  def handle_session_event(:message, %Omni.Message{role: :user} = message, socket) do
    if socket.assigns.current_turn == nil do
      assign(socket, :current_turn, streaming_turn(nil, message))
    else
      socket
    end
  end

  # Tree mirror. Session emits this after every tree mutation: turn commit
  # (with new node ids), navigate (empty new_nodes), and the apply_navigation
  # step inside branch ops (also empty new_nodes). Rebuild the turn list from
  # the new tree on each event — Turn.all walks the active path so navigates
  # and branches naturally drop turns that have left the path.
  #
  # The in-flight streaming turn (@current_turn) is rendered separately and
  # is not yet in the tree, so no filtering is needed — :turn always nils
  # @current_turn before :tree fires.
  def handle_session_event(:tree, %{tree: tree}, socket) do
    turns = Omni.UI.Turn.all(tree)

    socket
    |> assign(tree: tree, usage: Tree.usage(tree))
    |> stream(:turns, turns, reset: true)
  end

  # Persistence acks. The first save after starting a fresh session is the
  # signal that the session id is real — patch the URL so the user can
  # bookmark/share/reload.
  def handle_session_event(:store, {:saved, _kind}, socket) do
    if socket.assigns[:url_synced] do
      socket
    else
      socket
      |> push_patch(to: "/?session_id=#{socket.assigns.session_id}")
      |> assign(:url_synced, true)
    end
  end

  def handle_session_event(:store, {:error, kind, reason}, socket) do
    Logger.error("Session store error (#{kind}): #{inspect(reason)}")
    Omni.UI.notify(:error, "Couldn't save your changes.")
    socket
  end

  # Title changes (set via Omni.Session.set_title/2). Mirror to assigns; the
  # consumer can render @title if it surfaces a title bar.
  def handle_session_event(:title, title, socket) do
    assign(socket, :title, title)
  end

  # Best-effort sync if the session's agent state changes underneath us
  # (e.g. via a future Manager). The explicit update_session/2 paths already
  # keep model/thinking aligned, so this is defensive.
  def handle_session_event(:state, %_{model: model, opts: opts}, socket) do
    thinking = Keyword.get(opts, :thinking, false)

    socket
    |> assign(:model, model)
    |> assign(:thinking, thinking)
  end

  def handle_session_event(:status, _status, socket), do: socket

  def handle_session_event(:error, reason, socket) do
    Logger.error("Session error: #{inspect(reason)}")
    Omni.UI.notify(:error, format_error(reason))

    case socket.assigns.current_turn do
      nil ->
        socket

      turn ->
        assign(socket, :current_turn, %{turn | status: :error, error: format_error(reason)})
    end
  end

  # Catch-all for unhandled session events
  def handle_session_event(_event, _data, socket), do: socket

  # ── Helpers ──────────────────────────────────────────────────────

  defp streaming_turn(id, %Omni.Message{} = message) do
    %Omni.UI.Turn{
      id: id,
      status: :streaming,
      user_text: Enum.filter(message.content, &match?(%Omni.Content.Text{}, &1)),
      user_attachments: Enum.filter(message.content, &match?(%Omni.Content.Attachment{}, &1)),
      user_timestamp: message.timestamp
    }
  end

  defp format_error(%{message: message}) when is_binary(message), do: message
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(_reason), do: "Something went wrong. Please try again."

  defp notify_branch_error(:busy),
    do: Omni.UI.notify(:warning, "Wait for the current turn to finish.")

  defp notify_branch_error(:paused),
    do: Omni.UI.notify(:warning, "Resume the paused turn before branching.")

  defp notify_branch_error(:not_found),
    do: Omni.UI.notify(:warning, "Couldn't find that point in the conversation.")

  defp notify_branch_error(reason) do
    Logger.warning("Branch op failed: #{inspect(reason)}")
    Omni.UI.notify(:error, "Couldn't switch branches.")
  end
end
