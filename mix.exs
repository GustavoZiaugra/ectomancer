defmodule Ectomancer.MixProject do
  use Mix.Project

  @source_url "https://github.com/GustavoZiaugra/ectomancer"
  @version "0.1.0"

  def project do
    [
      app: :ectomancer,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Ectomancer",
      description: "Add an AI brain to your Phoenix app - Auto-expose Ecto schemas as MCP tools",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Ectomancer.Application, []}
    ]
  end

  defp package do
    [
      name: :ectomancer,
      files: ["lib", "mix.exs", "README.md", "LICENSE", "CHANGELOG.md"],
      maintainers: ["Gustavo Ziaugra"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "Ectomancer",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      source_url: @source_url,
      source_ref: "v#{@version}",
      groups_for_modules: [
        Core: [Ectomancer, Ectomancer.Tool, Ectomancer.Expose],
        Integration: [Ectomancer.Plug, Ectomancer.Repo],
        Utilities: [Ectomancer.SQLTool, Ectomancer.SchemaBuilder, Ectomancer.SchemaIntrospection]
      ]
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
      {:phoenix, ">= 1.7.0", optional: true},
      {:ecto, "~> 3.12", optional: true},
      {:plug, "~> 1.16", optional: true},

      # Development and testing
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
