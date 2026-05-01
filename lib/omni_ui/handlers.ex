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

  def handle_event("omni:navigate", %{"node_id" => node_id}, socket) do
    case Omni.Session.navigate(socket.assigns.session, node_id) do
      :ok ->
        {:noreply, push_event(socket, "omni:updated", %{})}

      {:error, reason} ->
        notify_branch_error(reason)
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

  def handle_info({OmniUI, :new_message, message}, socket) do
    socket = OmniUI.ensure_session(socket)
    :ok = Omni.Session.prompt(socket.assigns.session, message.content)
    {:noreply, assign(socket, :current_turn, streaming_turn(nil, message))}
  end

  # Editing a user message branches from its parent. Per `Omni.Session.branch/3`
  # semantics, the target is the assistant above the edited user (or `nil` for
  # a root user, which creates a new disjoint root). The new user + assistant
  # turn appends as children — opposite asymmetry from the old tree-owned-state
  # model, which navigated to the user's parent and pushed a sibling user.
  def handle_info({OmniUI, :edit_message, turn_id, message}, socket) do
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

  # Push a stub ToolUse on start so the header (icon, tool name) renders
  # immediately. The fully-formed struct replaces it on :tool_use_end.
  def handle_agent_event(:tool_use_start, %{id: id, name: name} = data, socket) do
    stub = %Omni.Content.ToolUse{id: id, name: name, input: Map.get(data, :input, %{})}

    update(socket, :current_turn, fn turn ->
      OmniUI.Turn.push_content(turn, stub)
    end)
  end

  def handle_agent_event(:tool_use_end, %{content: tool_use}, socket) do
    update(socket, :current_turn, fn turn ->
      OmniUI.Turn.replace_content(turn, tool_use)
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

  # Tree mirror. Session emits this after every tree mutation: turn commit
  # (with new node ids), navigate (empty new_nodes), and the apply_navigation
  # step inside branch ops (also empty new_nodes). Rebuild the turn list from
  # the new tree on each event — Turn.all walks the active path so navigates
  # and branches naturally drop turns that have left the path.
  #
  # During streaming, the in-flight turn is rendered separately via
  # @current_turn. We filter it out of the rebuilt list to avoid duplicating
  # it once the turn (or a continuation step) commits to the tree.
  def handle_agent_event(:tree, %{tree: tree, new_nodes: new_nodes}, socket) do
    socket = adopt_current_turn_id(socket, new_nodes)

    in_flight_id = if socket.assigns.current_turn, do: socket.assigns.current_turn.id

    turns =
      tree
      |> OmniUI.Turn.all()
      |> Enum.reject(&(&1.id == in_flight_id))

    socket
    |> assign(tree: tree, usage: Tree.usage(tree))
    |> stream(:turns, turns, reset: true)
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

  # ── Helpers ──────────────────────────────────────────────────────

  # New-message and edit flows start streaming with `current_turn.id == nil`
  # because the new user node hasn't been created yet. On the first commit
  # (the first :tree event with non-empty new_nodes after streaming starts),
  # the user node is the head of new_nodes — adopt it so subsequent rebuilds
  # can filter the in-flight turn out by id. Regen flows already have
  # current_turn.id set up front, and continuation commits leave it alone.
  defp adopt_current_turn_id(socket, [first_id | _]) do
    case socket.assigns.current_turn do
      %OmniUI.Turn{id: nil} = turn ->
        assign(socket, :current_turn, %{turn | id: first_id})

      _ ->
        socket
    end
  end

  defp adopt_current_turn_id(socket, []), do: socket

  defp streaming_turn(id, %Omni.Message{} = message) do
    %OmniUI.Turn{
      id: id,
      status: :streaming,
      user_text: Enum.filter(message.content, &match?(%Omni.Content.Text{}, &1)),
      user_attachments: Enum.filter(message.content, &match?(%Omni.Content.Attachment{}, &1)),
      user_timestamp: message.timestamp
    }
  end

  defp notify_branch_error(:busy),
    do: OmniUI.notify(:warning, "Wait for the current turn to finish.")

  defp notify_branch_error(:paused),
    do: OmniUI.notify(:warning, "Resume the paused turn before branching.")

  defp notify_branch_error(:not_found),
    do: OmniUI.notify(:warning, "Couldn't find that point in the conversation.")

  defp notify_branch_error(reason) do
    Logger.warning("Branch op failed: #{inspect(reason)}")
    OmniUI.notify(:error, "Couldn't switch branches.")
  end
end
