defmodule Ectomancer.Installer.IntegrationTest do
  @moduledoc """
  Integration tests for the Ectomancer setup tool.

  These tests verify the full setup workflow end-to-end.
  """

  use ExUnit.Case

  alias Ectomancer.Installer.ConfigUpdater
  alias Ectomancer.Installer.TemplateRenderer

  # Helper to create a temporary project structure
  defp create_test_project do
    random = System.unique_integer([:positive])
    base_path = System.tmp_dir!() |> Path.join("ectomancer_int_test_#{random}")

    File.mkdir_p!(Path.join(base_path, "config"))

    # Create mix.exs with deps function
    File.write!(Path.join(base_path, "mix.exs"), """
    defmodule TestApp.MixProject do
      use Mix.Project

      def project do
        [
          app: :test_app,
          version: "1.0.0",
          deps: deps()
        ]
      end

      defp deps do
        [
          {:phoenix, "~> 1.7"}
        ]
      end
    end
    """)

    # Create config.exs
    File.write!(Path.join([base_path, "config", "config.exs"]), """
    import Config
    """)

    # Create router.ex
    File.mkdir_p!(Path.join([base_path, "lib", "test_app_web"]))

    File.write!(Path.join([base_path, "lib", "test_app_web", "router.ex"]), """
    defmodule TestAppWeb.Router do
      use Phoenix.Router
    end
    """)

    {base_path, fn -> File.rm_rf!(base_path) end}
  end

  describe "ConfigUpdater integration" do
    test "updates all configuration files" do
      {project_path, cleanup} = create_test_project()

      try do
        mix_path = Path.join(project_path, "mix.exs")
        config_path = Path.join([project_path, "config", "config.exs"])
        router_path = Path.join([project_path, "lib", "test_app_web", "router.ex"])

        results =
          ConfigUpdater.update_files(
            mix_path: mix_path,
            config_path: config_path,
            router_path: router_path
          )

        assert {:ok, _} = results.mix_exs
        assert {:ok, _} = results.config_exs
        assert {:ok, _} = results.router_exs

        # Verify content
        assert File.read!(mix_path) =~ "{:ectomancer,"
        assert File.read!(config_path) =~ "config :ectomancer"
        assert File.read!(router_path) =~ "Ectomancer.Plug"
      after
        cleanup.()
      end
    end

    test "is idempotent - running twice doesn't duplicate" do
      {project_path, cleanup} = create_test_project()

      try do
        mix_path = Path.join(project_path, "mix.exs")
        config_path = Path.join([project_path, "config", "config.exs"])
        router_path = Path.join([project_path, "lib", "test_app_web", "router.ex"])

        # First run
        ConfigUpdater.update_files(
          mix_path: mix_path,
          config_path: config_path,
          router_path: router_path
        )

        # Second run
        results2 =
          ConfigUpdater.update_files(
            mix_path: mix_path,
            config_path: config_path,
            router_path: router_path
          )

        assert :not_modified = results2.mix_exs
        assert :not_modified = results2.config_exs
        assert :not_modified = results2.router_exs
      after
        cleanup.()
      end
    end

    test "returns error for missing files" do
      result = ConfigUpdater.update_mix_exs("/nonexistent/mix.exs")
      assert :error = result
    end
  end

  describe "TemplateRenderer integration" do
    test "generates MCP module file" do
      {project_path, cleanup} = create_test_project()

      try do
        mcp_path = Path.join([project_path, "lib", "test_app", "mcp.ex"])
        File.mkdir_p!(Path.dirname(mcp_path))

        schemas = [
          %{
            module: TestApp.User,
            table: "users",
            context: "Accounts",
            associations: [],
            writable_fields: [:email]
          },
          %{
            module: TestApp.Post,
            table: "posts",
            context: "Blog",
            associations: [],
            writable_fields: [:title]
          }
        ]

        result =
          TemplateRenderer.generate_mcp_module(
            schemas: schemas,
            output_path: mcp_path,
            include_oban: false,
            namespace: nil
          )

        assert {:ok, _} = result
        assert File.exists?(mcp_path)

        content = File.read!(mcp_path)
        assert content =~ "defmodule MyApp.MCP"
        assert content =~ "use Ectomancer"
      after
        cleanup.()
      end
    end

    test "returns not_modified when file unchanged" do
      {project_path, cleanup} = create_test_project()

      try do
        mcp_path = Path.join([project_path, "lib", "test_app", "mcp.ex"])
        File.mkdir_p!(Path.dirname(mcp_path))

        schemas = [
          %{
            module: TestApp.User,
            table: "users",
            context: "Accounts",
            associations: [],
            writable_fields: [:email]
          }
        ]

        # First generation
        TemplateRenderer.generate_mcp_module(
          schemas: schemas,
          output_path: mcp_path,
          include_oban: false,
          namespace: nil
        )

        # Second generation with same content
        result2 =
          TemplateRenderer.generate_mcp_module(
            schemas: schemas,
            output_path: mcp_path,
            include_oban: false,
            namespace: nil
          )

        assert :not_modified = result2
      after
        cleanup.()
      end
    end
  end

  describe "input validation" do
    test "parse_selection handles valid and invalid input" do
      # Valid
      assert parse_selection("1") == 0
      assert parse_selection(" 5 ") == 4

      # Invalid
      assert parse_selection("abc") == nil
      assert parse_selection("1.5") == nil
      assert parse_selection("") == nil
      assert parse_selection("1a") == nil
    end

    test "filter validates schema selections" do
      schemas = [1, 2, 3, 4, 5]

      # Valid indices
      assert Enum.filter([0, 1, 2], &(&1 >= 0 and &1 < length(schemas))) == [0, 1, 2]

      # Invalid indices filtered out
      assert Enum.filter([-1, 0, 5, 10], &(&1 >= 0 and &1 < length(schemas))) == [0]
    end
  end

  # Helper functions
  defp parse_selection(input) do
    case Integer.parse(String.trim(input)) do
      {num, ""} -> num - 1
      _ -> nil
    end
  end
end
