defmodule Ectomancer.MixProject do
  use Mix.Project

  def project do
    [
      app: :ectomancer,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Ectomancer.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # MCP Server Implementation (fork of Hermes, more actively maintained)
      {:anubis_mcp, "~> 0.17"},

      # JSON handling
      {:jason, "~> 1.4"},

      # Optional dependencies (only loaded if parent app uses them)
      {:phoenix, "~> 1.7", optional: true},
      {:ecto, "~> 3.12", optional: true},
      {:plug, "~> 1.16", optional: true},

      # Development and testing
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
