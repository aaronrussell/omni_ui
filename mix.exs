defmodule OmniUI.MixProject do
  use Mix.Project

  def project do
    [
      app: :omni_ui,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:omni, "~> 1.2"},
      {:omni, path: "../omni", override: true},
      {:omni_agent, "~> 0.2"},
      {:jason, "~> 1.4"},
      {:lucide_icons, "~> 2.0"},
      {:lumis, "~> 0.2.0"},
      {:mdex, "~> 0.11.6"},
      {:mdex_gfm, "~> 0.2"},
      {:mdex_mermaid, "~> 0.3.5"},
      {:phoenix_live_view, "~> 1.1.27"}
    ]
  end
end
