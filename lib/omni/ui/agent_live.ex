defmodule Omni.UI.AgentLive do
  @moduledoc """
  A batteries-included LiveView for agent chat.

  Mounts a complete chat interface with a sessions drawer, files panel,
  and the built-in tools (Files, REPL, WebFetch, WebSearch) wired up
  via `Omni.UI.Agent`. Drop it into your router for a working agent UI
  with minimal setup:

      # router.ex
      forward "/omni_files", Omni.UI.Files.Plug
      live "/", Omni.UI.AgentLive

  The files Plug must be mounted so the files panel can serve agent-generated
  files (HTML documents and code artifacts). See `Omni.UI.Files.Plug`
  for token signing and configuration details.

  ## Configuration

  Configure via `config :omni_ui, Omni.UI.AgentLive`:

    * `:providers` — list of provider atoms. Calls `Omni.list_models/1`
      for each at mount time, silently skipping any that fail. The
      combined list populates the model selector. Defaults to `[]`.

    * `:default_model` — `{provider, model_id}` tuple for the model
      the agent starts with. If omitted, falls back to the first model
      returned by the configured providers. If set but not found in the
      provider models, logs a warning and falls back to the first
      available model.

  At least one of `:default_model` or a non-empty `:providers` list is
  required.

  ### Multi-provider setup

      config :omni_ui, Omni.UI.AgentLive,
        providers: [:anthropic, :ollama],
        default_model: {:anthropic, "claude-sonnet-4-6"}

  ### Fixed model (no selector)

  Configure only `:default_model` with no `:providers` to lock the
  model and hide the selector:

      config :omni_ui, Omni.UI.AgentLive,
        default_model: {:anthropic, "claude-sonnet-4-6"}

  For more control over layout, tools, or event handling, skip this
  module and `use Omni.UI` in your own LiveView instead.
  """

  use Phoenix.LiveView
  use Omni.UI

  require Logger

  alias Omni.UI.FilesComponent
  alias Phoenix.LiveView.JS

  attr :current_turn, Omni.UI.Turn
  attr :usage, Omni.Usage, required: true
  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="relative h-screen w-full flex bg-omni-bg text-omni-text overflow-x-hidden">
      <.side_panel
        align="left"
        open={@open_sessions}
        close_event={JS.push("toggle", value: %{name: "sessions"})}>
        <.live_component
          module={Omni.UI.SessionsComponent}
          id="sessions"
          manager={Omni.UI.Sessions}
          current_id={@session_id} />
      </.side_panel>

      <.panel>
        <:header>
          <.chat_panel_header
            title={@title || "Untitled"}
            open_sessions={@open_sessions}
            open_files={@open_files} />
        </:header>

        <.chat_interface>
          <.turn_list
            stream={@streams.turns}
            tool_components={@tool_components} />

          <.turn
            :if={@current_turn}
            turn={@current_turn}
            tool_components={@tool_components} />

          <:editor>
            <.editor
              model={@model}
              model_options={@model_options}
              thinking={@thinking}
              usage={@usage} />
          </:editor>

          <:footer>
            <p>Boring footer here. <a href="#todo">Privacy Policy</a></p>
          </:footer>
        </.chat_interface>
      </.panel>

      <.side_panel
        align="right"
        open={@open_files}
        close_event={JS.push("toggle", value: %{name: "files"})}
        outer_class="lg:w-96 xl:w-128 2xl:w-160"
        inner_class="w-screen md:w-96 xl:w-128 2xl:w-160">
        <.live_component
          module={FilesComponent}
          id="files-panel"
          session_id={@session_id} />
      </.side_panel>

      <.notifications stream={@streams.notifications} />
    </div>
    """
  end

  # Chat panel header — extracted as a function component for readability,
  # not for reuse.
  attr :title, :string, required: true
  attr :open_sessions, :boolean
  attr :open_files, :boolean

  defp chat_panel_header(assigns) do
    ~H"""
    <.panel_header title={@title}>
      <:left>
        <button
          class={[
            "flex items-center justify-center size-8 rounded cursor-pointer",
            "text-omni-text-1 hover:text-omni-accent-1 hover:bg-omni-accent-2/10"
          ]}
          title="Sessions"
          phx-click={JS.push("toggle", value: %{name: "sessions"})}>
          <%= if @open_sessions do %>
            <Lucideicons.panel_left_close class="size-4" />
          <% else %>
            <Lucideicons.panel_left_open class="size-4" />
          <% end %>
        </button>
      </:left>

      <:right>
        <button
          class={[
            "flex items-center justify-center size-8 rounded cursor-pointer",
            "text-omni-text-1 hover:text-omni-accent-1 hover:bg-omni-accent-2/10"
          ]}
          title="Open files panel"
          phx-click={JS.push("toggle", value: %{name: "files"})}>
          <%= if @open_files do %>
            <Lucideicons.panel_right_close class="size-4" />
          <% else %>
            <Lucideicons.panel_right_open class="size-4" />
          <% end %>
        </button>
      </:right>
    </.panel_header>
    """
  end

  # Side panel — used only in the above render/1 function.
  attr :align, :string, values: ["left", "right"], required: true
  attr :open, :boolean, required: true
  attr :close_event, Phoenix.LiveView.JS, required: true
  attr :outer_class, :string, default: "lg:w-72"
  attr :inner_class, :string, default: "w-72"
  slot :inner_block, required: true

  defp side_panel(assigns) do
    ~H"""
    <div
      class={[
        "absolute top-12 bottom-0 w-0 lg:relative lg:inset-auto",
        "flex flex-col",
        "transition-[width] duration-300 ease-out",
        if(@align == "left", do: "left-0 z-20 items-start", else: "right-0 z-10 items-end"),
        if(@open, do: @outer_class),
      ]}>
      <div
        class={[
          "lg:hidden absolute -z-5 w-screen h-full bg-black/25 transition-opacity",
          if(@align == "right", do: "right-0"),
          if(@open, do: "visible opacity-100", else: "invisible opacity-0"),
        ]}
        phx-click={@close_event} />
      <div
        class={[
          "h-full transition-transform duration-300 ease-out",
          @inner_class,
          if(@open,
            do: "translate-x-0",
            else: if(@align == "left", do: "-translate-x-full", else: "translate-x-full")
          ),
          if(@align == "left",
            do: "border-r border-omni-border-2 shadow-[4px_0px_6px_-1px_rgba(0,0,0,0.1)]",
            else: "border-l border-omni-border-2 shadow-[-4px_0px_6px_-1px_rgba(0,0,0,0.1)]"
          )
        ]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    config = Application.get_env(:omni_ui, __MODULE__, [])
    model_options = list_provider_models(config)
    model = resolve_default_model(config, model_options)

    if connected?(socket), do: Omni.UI.Sessions.subscribe()

    {:ok,
     socket
     |> assign(
       model_options: model_options,
       open_sessions: true,
       open_files: false
     )
     |> init_session(
       agent_module: Omni.UI.Agent,
       tool_components: %{
         "files" => &Omni.UI.ToolsUI.files_tool_use/1,
         "repl" => &Omni.UI.ToolsUI.repl_tool_use/1
       },
       model: model
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    if connected?(socket) do
      try do
        {:noreply, attach_session(socket, id: params["session_id"])}
      rescue
        _e in RuntimeError ->
          notify(:warning, "Session not found.")
          {:noreply, push_patch(socket, to: "/")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("open_session", %{"session-id" => id}, socket) do
    {:noreply, push_patch(socket, to: "/?session_id=#{id}")}
  end

  def handle_event("new_session", _params, socket) do
    {:noreply, push_patch(socket, to: "/")}
  end

  def handle_event("open_file", %{"filename" => filename}, socket) do
    send_update(FilesComponent,
      id: "files-panel",
      action: {:view, filename}
    )

    {:noreply, assign(socket, :open_files, true)}
  end

  def handle_event("toggle", %{"name" => name}, socket) do
    key = String.to_existing_atom("open_#{name}")
    {:noreply, assign(socket, key, not socket.assigns[key])}
  end

  @impl Phoenix.LiveView
  def handle_info({:manager, _, _, _} = msg, socket) do
    send_update(Omni.UI.SessionsComponent, id: "sessions", manager_event: msg)
    {:noreply, socket}
  end

  def handle_info(:active_session_deleted, socket) do
    {:noreply, push_patch(socket, to: "/")}
  end

  @impl Omni.UI
  def session_event(:tool_result, %{name: name}, socket) when name in ["files", "repl"] do
    send_update(FilesComponent, id: "files-panel", action: :rescan)
    socket
  end

  def session_event(_event, _data, socket), do: socket

  defp list_provider_models(config) do
    config
    |> Keyword.get(:providers, [])
    |> Enum.flat_map(fn provider_id ->
      case Omni.list_models(provider_id) do
        {:ok, models} -> models
        {:error, _} -> []
      end
    end)
  end

  defp resolve_default_model(config, model_options) do
    case {Keyword.get(config, :default_model), model_options} do
      {{_, _} = ref, [model | _]} ->
        if model_exists?(ref, model_options) do
          ref
        else
          Logger.warning(
            "Omni.UI.AgentLive: configured :default_model #{inspect(ref)} " <>
              "not found in provider models, falling back to first available model"
          )

          model
        end

      {{_, _} = ref, []} ->
        ref

      {nil, [model | _]} ->
        model

      {nil, []} ->
        raise ArgumentError, """
        Omni.UI.AgentLive requires at least one of :default_model or \
        a non-empty :providers list.

        Configure in your application config:

            config :omni_ui, Omni.UI.AgentLive,
              providers: [:anthropic],
              default_model: {:anthropic, "claude-sonnet-4-6"}
        """
    end
  end

  defp model_exists?({provider_id, model_id}, model_options) do
    Enum.any?(model_options, fn model ->
      {p, id} = Omni.Model.to_ref(model)
      p == provider_id and id == model_id
    end)
  end
end
