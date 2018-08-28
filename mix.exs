defmodule ElixiumNode.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixium_node,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      default_task: "node"
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
      {:elixium_core, "~> 0.2"}
    ]
  end
end
