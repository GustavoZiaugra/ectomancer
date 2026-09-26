defmodule Ectomancer.MixProject do
  use Mix.Project

  @source_url "https://github.com/GustavoZiaugra/ectomancer"
  @version "2.0.0"

  def project do
    [
      app: :ectomancer,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      name: "Ectomancer",
      description: "Add an AI brain to your Phoenix app - Auto-expose Ecto schemas as MCP tools",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url,
      dialyzer: [plt_add_apps: [:mix, :ex_unit]],
      test_coverage: [summary: [threshold: 80]]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

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
      files: ["lib", "priv", "mix.exs", "README.md", "LICENSE", "CHANGELOG.md"],
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
        Integration: [
          Ectomancer.Plug,
          Ectomancer.Repo,
          Ectomancer.RouteIntrospection,
          Ectomancer.ObanBridge
        ],
        Utilities: [Ectomancer.SchemaBuilder, Ectomancer.SchemaIntrospection],
        Installer: [
          Ectomancer.Installer.ConfigUpdater,
          Ectomancer.Installer.DependencyChecker,
          Ectomancer.Installer.SchemaDiscovery,
          Ectomancer.Installer.TemplateRenderer,
          Ectomancer.Igniter
        ]
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # MCP Server Implementation (fork of Hermes, more actively maintained)
      {:anubis_mcp, "~> 1.14"},

      # JSON handling
      {:jason, "~> 1.4"},

      # Transitive via anubis_mcp -> finch. Floor >= 1.10.1 fixes
      # GHSA-g83f-2j6r-q6m4, GHSA-7p8w-j234-7qc8 and GHSA-rj5m-69wp-cxq9
      # (HTTP/1 request smuggling + memory/CPU exhaustion DoS)
      {:mint, ">= 1.10.1 and < 2.0.0", optional: true},

      # Noun inflection (pluralize/singularize) for tool name generation
      {:plurality, "~> 0.3"},

      # Optional dependencies (only loaded if parent app uses them)
      # Floor >= 1.7.24 fixes GHSA-628h-q48j-jr6q (long-poll NDJSON body splitting DoS)
      # and GHSA-6983-jfq8-485w / GHSA-63mc-hw7g-86rr (channel join + presence DoS)
      {:phoenix, ">= 1.7.24", optional: true},
      {:ecto, "~> 3.12", optional: true},
      # Floor >= 1.19.2 fixes GHSA-468c-vq7p-gh64 (unbounded multipart header buffer DoS)
      {:plug, ">= 1.19.2 and < 2.0.0", optional: true},
      {:oban, "~> 2.18", optional: true},
      # Floor >= 0.8.4 fixes GHSA-cj7w-j579-gc42 (terminal escape sequence injection)
      {:igniter, "~> 0.8.4", optional: true},

      # Development and testing
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # Database testing
      {:ecto_sqlite3, "~> 0.22", only: :test}
    ]
  end
end
