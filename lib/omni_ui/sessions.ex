defmodule OmniUI.Sessions do
  @moduledoc """
  Default `Omni.Session.Manager` shipped with OmniUI.

  Configure the store under the `:omni_ui` app and add the module to your
  application supervision tree:

      # config/config.exs
      config :omni_ui, OmniUI.Sessions,
        store:
          {Omni.Session.Store.FileSystem,
           base_path: "priv/omni/sessions", otp_app: :my_app}

      # application.ex
      children = [OmniUI.Sessions]

  Start-time opts override app-env values, so a host app can compute
  config at boot when needed:

      children = [
        {OmniUI.Sessions,
           store: {Omni.Session.Store.FileSystem, base_path: dynamic_path(), otp_app: :my_app}}
      ]

  Consumers wanting multiple Managers (e.g. multi-tenant isolation)
  define their own modules — `defmodule MyApp.Sessions, do: use
  Omni.Session.Manager, otp_app: :my_app` — and pass them to
  `OmniUI.attach_session/2` via the `:manager` option.
  """

  use Omni.Session.Manager, otp_app: :omni_ui

  def session_dir(session_id) do
    base_dir = Application.fetch_env!(:omni_ui, :sessions_base_dir)
    Path.join([base_dir, session_id])
  end

  def session_files_dir(session_id) do
    Path.join([session_dir(session_id), "files"])
  end
end
