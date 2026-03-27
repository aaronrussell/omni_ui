defmodule OmniUI.AgentLive do
  use Phoenix.LiveView
  import OmniUI.Components

  require Logger

  attr :current_turn, OmniUI.Turn
  attr :usage, Omni.Usage, required: true
  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative size-full flex">
      <div class="h-full w-full">
        <.chat_interface>
          <.message_list id="turns" phx-update="stream">
            <.turn
              :for={{dom_id, turn} <- @streams.turns}
              id={dom_id}
              turn={turn} />
          </.message_list>

          <.turn :if={@current_turn} turn={@current_turn} />

          <:toolbar>
            <.toolbar
              model={@model}
              model_options={@model_options}
              thinking={@thinking}
              thinking_options={@thinking_options}
              usage={@usage} />
          </:toolbar>

          <:footer>
            <p>Boring footer here. <a href="#todo">Privacy Policy</a></p>
          </:footer>
        </.chat_interface>
      </div>

      <!-- TODO : artifacts button -->

      <div class="h-full hidden">
        <!-- TODO : artifacts panel -->
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    tree = %OmniUI.Tree{}
    tree = OmniUI.TreeFaker.generate()

    turns = OmniUI.Turn.all(tree)
    usage = OmniUI.Tree.usage(tree)

    {:ok, model} = Omni.get_model(:ollama, "qwen3.5:4b")

    {:ok, agent} =
      Omni.Agent.start_link(
        model: model,
        context: Omni.context(messages: OmniUI.Tree.messages(tree)),
        opts: [
          thinking: false
        ]
      )

    model_options =
      :persistent_term.get({Omni, :provider_ids}, %{})
      |> Map.values()
      |> Enum.sort()
      |> Enum.map(fn provider_id ->
        {:ok, models} = Omni.list_models(provider_id)

        provider_name =
          models
          |> hd()
          |> Map.get(:provider)
          |> Module.split()
          |> List.last()

        %{
          label: provider_name,
          options:
            models
            |> Enum.sort_by(& &1.name)
            |> Enum.map(&%{value: "#{provider_id}:#{&1.id}", label: &1.name})
        }
      end)

    thinking_options =
      [false, :low, :medium, :high, :max]
      |> Enum.reverse()
      |> Enum.map(fn val ->
        value = to_string(val)
        label = if val == false, do: "Off", else: String.capitalize(value)
        %{value: value, label: label}
      end)

    socket =
      socket
      |> assign(
        agent: agent,
        tree: tree,
        current_turn: nil,
        model: model,
        model_options: model_options,
        thinking: false,
        thinking_options: thinking_options,
        usage: usage
      )
      |> stream(:turns, turns)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_model", %{"value" => value}, socket) do
    [provider, model_id] = String.split(value, ":", parts: 2)
    {:ok, model} = Omni.get_model(String.to_existing_atom(provider), model_id)
    :ok = Omni.Agent.set_state(socket.assigns.agent, :model, model)
    {:noreply, assign(socket, model: model)}
  end

  def handle_event("copy_message", %{"turn_id" => turn_id, "role" => role}, socket) do
    turn = OmniUI.Turn.get(socket.assigns.tree, turn_id)
    text = OmniUI.Turn.get_text(turn, String.to_existing_atom(role))
    {:noreply, push_event(socket, "omni:clipboard", %{text: text})}
  end

  def handle_event("navigate", %{"node_id" => node_id}, socket) do
    {:ok, tree} = OmniUI.Tree.navigate(socket.assigns.tree, node_id)
    tree = OmniUI.Tree.extend(tree)
    turns = OmniUI.Turn.all(tree)

    socket =
      socket
      |> assign(tree: tree)
      |> stream(:turns, turns, reset: true)
      |> push_event("omni:updated", %{})

    {:noreply, socket}
  end

  def handle_event("regenerate", %{"turn_id" => turn_id}, socket) do
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

  def handle_event("select_thinking", %{"value" => value}, socket) do
    thinking = String.to_existing_atom(value)
    :ok = Omni.Agent.set_state(socket.assigns.agent, :opts, &Keyword.put(&1, :thinking, thinking))
    {:noreply, assign(socket, thinking: thinking)}
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
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

    {:noreply, socket}
  end

  def handle_info({:agent, _pid, :thinking_start, _data}, socket) do
    socket =
      update(socket, :current_turn, fn turn ->
        OmniUI.Turn.push_content(turn, %Omni.Content.Thinking{text: ""})
      end)

    {:noreply, socket}
  end

  def handle_info({:agent, _pid, :text_start, _data}, socket) do
    socket =
      update(socket, :current_turn, fn turn ->
        OmniUI.Turn.push_content(turn, %Omni.Content.Text{text: ""})
      end)

    {:noreply, socket}
  end

  def handle_info({:agent, _pid, delta_type, %{delta: delta}}, socket)
      when delta_type in [:thinking_delta, :text_delta] do
    # TODO - debounce this
    socket =
      update(socket, :current_turn, fn turn ->
        OmniUI.Turn.push_delta(turn, delta)
      end)

    {:noreply, socket}
  end

  def handle_info({:agent, _pid, :tool_use_end, %{content: tool_use}}, socket) do
    socket =
      update(socket, :current_turn, fn turn ->
        OmniUI.Turn.push_content(turn, tool_use)
      end)

    {:noreply, socket}
  end

  def handle_info({:agent, _pid, :tool_result, tool_result}, socket) do
    socket =
      update(socket, :current_turn, fn turn ->
        OmniUI.Turn.put_tool_result(turn, tool_result)
      end)

    {:noreply, socket}
  end

  def handle_info({:agent, _pid, :done, response}, socket) do
    [_user_msg | rest_msgs] = response.messages
    {[res_id | _], tree} = tree_push_all(socket.assigns.tree, rest_msgs, response.usage)

    user_node_id = socket.assigns.current_turn.id
    parent_id = tree.nodes[user_node_id].parent_id
    edits = OmniUI.Tree.children(tree, parent_id)
    regens = OmniUI.Tree.children(tree, user_node_id)

    turn = OmniUI.Turn.new(user_node_id, response.messages, response.usage)
    turn = %{turn | res_id: res_id, edits: edits, regens: regens}

    socket =
      socket
      |> assign(current_turn: nil, tree: tree)
      |> update(:usage, &Omni.Usage.add(&1, response.usage))
      |> stream_insert(:turns, turn)

    {:noreply, socket}
  end

  def handle_info({:agent, _pid, :error, reason}, socket) do
    Logger.error("Agent error: #{inspect(reason)}")

    turn = Map.put(socket.assigns.current_turn, :status, :error)

    socket =
      socket
      |> assign(current_turn: nil)
      |> stream_insert(:turns, turn)
      |> put_flash(:error, "Something went wrong")

    {:noreply, socket}
  end

  # Catch-all
  def handle_info({:agent, _pid, _type, _data}, socket) do
    {:noreply, socket}
  end

  # Helpers

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
