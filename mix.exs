defmodule OmniUI.MixProject do
  use Mix.Project

  def project do
    [
      app: :omni_ui,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mdex, "~> 0.11.6"},
      {:mdex_gfm, "~> 0.2"},
      {:mdex_mermaid, "~> 0.3.5"},
      {:omni, "~> 1.1.0"},
      {:phoenix_live_view, "~> 1.1.27"}
    ]
  end
end
