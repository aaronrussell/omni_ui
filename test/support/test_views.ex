defmodule OmniUI.Test.MinimalView do
  @moduledoc false
  use Phoenix.LiveView
  use OmniUI

  @impl Phoenix.LiveView
  def render(assigns), do: ~H"<div>minimal</div>"

  @impl Phoenix.LiveView
  def mount(_params, _session, socket), do: {:ok, socket}
end

defmodule OmniUI.Test.CustomHandlersView do
  @moduledoc false
  use Phoenix.LiveView
  use OmniUI

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

defmodule OmniUI.Test.CustomAgentEventView do
  @moduledoc false
  use Phoenix.LiveView
  use OmniUI

  @impl Phoenix.LiveView
  def render(assigns), do: ~H"<div>agent_event</div>"

  @impl Phoenix.LiveView
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl OmniUI
  def agent_event(event, data, socket) do
    assign(socket, :last_agent_event, {event, data})
  end
end

defmodule OmniUI.Test.BadAgentEventView do
  @moduledoc false
  use Phoenix.LiveView
  use OmniUI

  @impl Phoenix.LiveView
  def render(assigns), do: ~H"<div>bad</div>"

  @impl Phoenix.LiveView
  def mount(_params, _session, socket), do: {:ok, socket}

  # The runtime case discriminator prevents the type-checker from
  # narrowing this function's return to a static atom — so the macro's
  # `%Socket{} = s` clause typechecks and we still hit the raise at
  # runtime when the test invokes us with a real socket.
  @impl OmniUI
  def agent_event(_event, _data, socket) do
    case socket do
      %Phoenix.LiveView.Socket{} -> :not_a_socket
      other -> other
    end
  end
end
