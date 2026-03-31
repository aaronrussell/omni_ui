defmodule OmniUIDevWeb.Router do
  use OmniUIDevWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {OmniUIDevWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/" do
    pipe_through :browser
    live "/", OmniUI.AgentLive
  end

  forward "/omni_artifacts", OmniUI.Artifacts.Plug

  # Other scopes may use custom stacks.
  # scope "/api", OmniUIDevWeb do
  #   pipe_through :api
  # end
end
