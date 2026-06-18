defmodule Omni.UI.TestEndpoint do
  @moduledoc false
  # Minimal endpoint module for render_component/2. The LiveViewTest helpers
  # store this on the socket struct but don't call any functions on it during
  # static rendering, so a bare module is sufficient.
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
