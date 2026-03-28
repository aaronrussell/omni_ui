defmodule OmniUI.TestEndpoint do
  @moduledoc false
  # Minimal endpoint module for render_component/2. The LiveViewTest helpers
  # store this on the socket struct but don't call any functions on it during
  # static rendering, so a bare module is sufficient.
end

defmodule OmniUI.ComponentCase do
  @moduledoc """
  Test case for OmniUI components.

  Sets up `Phoenix.LiveViewTest` helpers with a test endpoint so that
  `render_component/2` and `rendered_to_string/1` work for both function
  components and LiveComponents.

  ## Usage

      use OmniUI.ComponentCase
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.Component
      import Phoenix.LiveViewTest
      import OmniUI.Components

      @endpoint OmniUI.TestEndpoint
    end
  end
end
