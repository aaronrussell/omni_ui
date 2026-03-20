#!/usr/bin/env elixir
Mix.install([
  {:phoenix_playground, "~> 0.1.8"},
  {:omni_ui, path: "../"}
])

defmodule DemoLayout do
  use Phoenix.Component

  def render("live.html", assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="h-full">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <.live_title>
          <%= assigns[:page_title] || "Phoenix Playground" %>
        </.live_title>
        <script src="/assets/phoenix/phoenix.js"></script>
        <script src="/assets/phoenix_live_view/phoenix_live_view.js"></script>
        <script>
          window.hooks = {}
          window.uploaders = {}

          let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, { hooks, uploaders })
          liveSocket.connect()

          window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
            reloader.enableServerLogs()
            window.liveReloader = reloader
          })
        </script>
        <script src="https://cdn.tailwindcss.com"></script>
        <style>
          [data-phx-session], [data-phx-teleported-src] { display: contents }
        </style>
      </head>
      <body class="h-full min-h-screen">
        <%= @inner_content %>
      </body>
    </html>
    """
  end
end

defmodule DemoRouter do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DemoLayout, :live}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/" do
    pipe_through :browser

    live "/", OmniUI.ChatLive
  end
end

PhoenixPlayground.start(plug: DemoRouter)
