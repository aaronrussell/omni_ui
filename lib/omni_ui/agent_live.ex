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
            <.turn :for={{dom_id, turn} <- @streams.turns} id={dom_id} turn={turn} />
          </.message_list>

          <:current_turn :if={@current_turn}>
            <.turn turn={@current_turn} />
          </:current_turn>

          <:toolbar>
            <% {provider_id, model_id} = Omni.Model.to_ref(@model) %>
            <.select
              id="model-select"
              options={@model_options}
              value={"#{provider_id}:#{model_id}"}
              event="select_model"
            />
          </:toolbar>
          <:toolbar :if={@model.reasoning}>
            <.select
              id="thinking-select"
              options={@thinking_options}
              value={to_string(@thinking)}
              event="select_thinking"
              prompt="Thinking"
            />
          </:toolbar>
          <:toolbar align="end">
            <.usage_block usage={@usage} />
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
    tree = %Omni.MessageTree{}
    # tree = OmniUI.FakeTree.generate()

    parent_map =
      [nil | tree.active_path]
      |> Enum.reduce(%{}, fn parent, acc ->
        Map.put(acc, parent, Omni.MessageTree.children(tree, parent))
      end)

    turns = Enum.map(tree, &OmniUI.Turn.from_omni(elem(&1, 1), parent_map))
    usage = Omni.MessageTree.usage(tree)

    {:ok, model} = Omni.get_model(:anthropic, "claude-haiku-4-5")
    {:ok, agent} = Omni.Agent.start_link(model: model, tree: tree)

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

  def handle_event("select_thinking", %{"value" => value}, socket) do
    thinking = String.to_existing_atom(value)
    :ok = Omni.Agent.set_state(socket.assigns.agent, :opts, &Keyword.put(&1, :thinking, thinking))
    {:noreply, assign(socket, thinking: thinking)}
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    # :ok = Omni.Agent.prompt(socket.assigns.agent, message.content)

    current_turn = %OmniUI.Turn{
      status: :streaming,
      user_text: Enum.filter(message.content, &match?(%Omni.Content.Text{}, &1)),
      user_attachments: Enum.filter(message.content, &match?(%Omni.Content.Attachment{}, &1)),
      user_timestamp: message.timestamp
    }

    socket = assign(socket, current_turn: current_turn)

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
    # todo - build parent_map and pass it to Turn.from_omni
    socket =
      socket
      |> assign(current_turn: nil)
      |> update(:usage, &Omni.Usage.add(&1, response.turn.usage))
      |> stream_insert(:turns, OmniUI.Turn.from_omni(response.turn, %{}))

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
end
