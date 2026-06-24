defmodule Omni.UI.TestErrorHTML do
  @moduledoc false
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule Omni.UI.TestRouter do
  @moduledoc false
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/" do
    pipe_through(:browser)
    live("/", Omni.UI.AgentLive)
  end
end

defmodule Omni.UI.TestEndpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :omni_ui

  @session_options [
    store: :cookie,
    key: "_omni_ui_test_key",
    signing_salt: "test_salt"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
  )

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.Session, @session_options)
  plug(Omni.UI.TestRouter)
end

defmodule Omni.UI.ComponentCase do
  @moduledoc """
  Test case for Omni.UI components.

  Sets up `Phoenix.LiveViewTest` helpers with a test endpoint so that
  `render_component/2` and `rendered_to_string/1` work for both function
  components and LiveComponents.

  ## Usage

      use Omni.UI.ComponentCase
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.Component
      import Phoenix.LiveViewTest
      import Omni.UI.ChatUI
      import Omni.UI.CoreUI

      @endpoint Omni.UI.TestEndpoint
    end
  end
end
