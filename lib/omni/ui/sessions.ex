defmodule Omni.UI.Sessions do
  @moduledoc """
  Default `Omni.Session.Manager` shipped with Omni.UI.

  Configure the store under the `:omni_ui` app and add the module to your
  application supervision tree:

      # config/config.exs
      config :omni_ui, Omni.UI.Sessions,
        sessions_base_dir: "/absolute/path/to/sessions",
        store:
          {Omni.Session.Stores.FileSystem,
           base_dir: "/absolute/path/to/sessions"},
        title_generator: {:anthropic, "claude-haiku-4-5"}

      # application.ex
      children = [Omni.UI.Sessions]

  Start-time opts override app-env values, so a host app can compute
  config at boot when needed.

  Consumers wanting multiple Managers (e.g. multi-tenant isolation)
  define their own modules — `defmodule MyApp.Sessions, do: use
  Omni.Session.Manager, otp_app: :my_app` — and pass them to
  `Omni.UI.attach_session/2` via the `:manager` option.
  """

  use Omni.Session.Manager, otp_app: :omni_ui

  def session_dir(session_id) do
    config = Application.get_env(:omni_ui, __MODULE__, [])

    base_dir =
      Keyword.get(config, :sessions_base_dir) ||
        raise ArgumentError,
              "missing :sessions_base_dir in config :omni_ui, Omni.UI.Sessions"

    Path.join([base_dir, session_id])
  end

  def session_files_dir(session_id) do
    Path.join([session_dir(session_id), "files"])
  end
end
