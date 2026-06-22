defmodule Omni.UI.Test.MinimalView do
  @moduledoc false
  use Phoenix.LiveView
  use Omni.UI

  @impl Phoenix.LiveView
  def render(assigns), do: ~H"<div>minimal</div>"

  @impl Phoenix.LiveView
  def mount(_params, _session, socket), do: {:ok, socket}
end

defmodule Omni.UI.Test.CustomHandlersView do
  @moduledoc false
  use Phoenix.LiveView
  use Omni.UI

  @impl Phoenix.LiveView
  def render(assigns), do: ~H"<div>custom</div>"

  @impl Phoenix.LiveView
  def mount(_params, _session, socket), do: {:ok, socket}

  def handle_event("my:custom_event", params, socket) do
    {:noreply, assign(socket, :custom_event, params)}
  end

  def handle_info({:my_message, data}, socket) do
    {:noreply, assign(socket, :my_message, data)}
  end
end

defmodule Omni.UI.Test.CustomSessionEventView do
  @moduledoc false
  use Phoenix.LiveView
  use Omni.UI

  @impl Phoenix.LiveView
  def render(assigns), do: ~H"<div>session_event</div>"

  @impl Phoenix.LiveView
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl Omni.UI
  def session_event(event, data, socket) do
    assign(socket, :last_session_event, {event, data})
  end
end

defmodule Omni.UI.Test.BadSessionEventView do
  @moduledoc false
  use Phoenix.LiveView
  use Omni.UI

  @impl Phoenix.LiveView
  def render(assigns), do: ~H"<div>bad</div>"

  @impl Phoenix.LiveView
  def mount(_params, _session, socket), do: {:ok, socket}

  # Branching on a runtime value (socket.id) keeps the return type wide
  # enough that the macro's `%Socket{} = s` clause stays reachable to
  # the type checker. A bare `:not_a_socket` return would cause Elixir
  # 1.20+ to warn that the socket match can never succeed.
  @impl Omni.UI
  def session_event(_event, _data, socket) do
    case socket.id do
      "will_not_be_this" -> socket
      _other -> :not_a_socket
    end
  end
end
