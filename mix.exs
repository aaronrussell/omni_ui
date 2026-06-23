defmodule Omni.UI.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/aaronrussell/omni_ui"

  def project do
    [
      app: :omni_ui,
      name: "Omni UI",
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      docs: docs(),
      package: pkg()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:omni, "~> 1.5"},
      {:omni_agent, "~> 0.5"},
      {:omni_tools, "~> 0.4"},
      {:jason, "~> 1.4"},
      {:lucide_icons, "~> 2.0"},
      {:lumis, "~> 0.2.0"},
      {:mdex, "~> 0.11.6"},
      {:mdex_gfm, "~> 0.2"},
      {:mdex_mermaid, "~> 0.3.5"},
      {:phoenix_live_view, "~> 1.1.27"},

      # dev dependencies
      {:ex_doc, "~> 0.40", only: :dev, runtime: false, warn_if_outdated: true}
    ]
  end

  defp docs do
    [
      main: "Omni.UI",
      source_url: @source_url,
      source_ref: "v#{@version}",
      homepage_url: @source_url,
      extras: ["CHANGELOG.md"],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      groups_for_modules: [
        Components: ~r/\w+(Component|UI)$/,
        Data: [
          Omni.UI.Notification,
          Omni.UI.Turn
        ],
        Files: ~r/^Omni\.UI\.Files\..+$/
      ]
    ]
  end

  defp pkg do
    [
      description:
        "Agent chat UI for Elixir — ready-made LiveView interface and components for building Omni-powered agents.",
      licenses: ["Apache-2.0"],
      maintainers: ["Aaron Russell"],
      files: ~w(lib .formatter.exs mix.exs CHANGELOG.md LICENSE README.md),
      links: %{
        "GitHub" => @source_url
      }
    ]
  end
end
