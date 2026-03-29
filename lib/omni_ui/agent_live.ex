defmodule OmniUI.AgentLive do
  use Phoenix.LiveView
  import OmniUI.Components

  attr :current_turn, OmniUI.Turn
  attr :usage, Omni.Usage, required: true
  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative size-full flex">
      <div class="h-full w-full">
        <.chat_interface>
          <.message_list id="turns" phx-update="stream">
            <.live_component
              :for={{dom_id, turn} <- @streams.turns}
              module={OmniUI.TurnComponent}
              id={dom_id}
              turn={turn} />
          </.message_list>

          <.turn :if={@current_turn} id="current-turn">
            <:user>
              <.user_message text={@current_turn.user_text} attachments={@current_turn.user_attachments} />
              <.timestamp time={@current_turn.user_timestamp} />
            </:user>
            <:assistant>
              <.assistant_message
                content={@current_turn.content}
                tool_results={@current_turn.tool_results}
                streaming={true} />
            </:assistant>
          </.turn>

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
    # tree = %OmniUI.Tree{}
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
  def handle_event(event, params, socket),
    do: OmniUI.Handlers.handle_event(event, params, socket)

  @impl true
  def handle_info(message, socket),
    do: OmniUI.Handlers.handle_info(message, socket)
end
