defmodule ElixiumNode.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixium_node,
      version: "1.1.3",
      elixir: "~> 1.7",
      start_permanent: true,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {ElixiumNode, []},
      extra_applications: [
        :ssl,
        :logger,
        :inets,
        :crypto,
        :elixium_core
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:elixium_core, "~> 0.6"},
      {:pico, path: "../../pico"},
      {:poison, "~> 3.1"},
      {:distillery, "~> 2.0"},
      {:toml, "~> 0.5"},
      {:logger_file_backend, "~> 0.0.10"}
    ]
  end
end
