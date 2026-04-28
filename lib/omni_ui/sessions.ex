defmodule OmniUI.Sessions do
  @moduledoc """
  Default `Omni.Session.Manager` shipped with OmniUI.

  Add to your application supervision tree with a configured store:

      children = [
        {OmniUI.Sessions,
           store: {Omni.Session.Store.FileSystem, base_path: "priv/sessions"}}
      ]

  Consumers wanting multiple Managers (e.g. multi-tenant isolation) define
  their own modules — `defmodule MyApp.Sessions, do: use Omni.Session.Manager`
  — and pass them to `OmniUI.attach_session/2` via the `:manager` option.
  """

  use Omni.Session.Manager
end
