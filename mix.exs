defmodule ElixiumNode.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixium_node,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: true,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {ElixiumNodeApp, []},
      applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:elixium_core, "~> 0.2"},
      # {:local_dependency, path: "../core", app: false},
      {:logger_file_backend, "~> 0.0.10"}
    ]
  end
end
