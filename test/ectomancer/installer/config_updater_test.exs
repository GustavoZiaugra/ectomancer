defmodule Ectomancer.Installer.ConfigUpdaterTest do
  use ExUnit.Case, async: true
  alias Ectomancer.Installer.ConfigUpdater

  describe "update_mix_exs/1" do
    setup do
      # Create a temp directory for testing
      path = System.tmp_dir!() |> Path.join("test_mix_#{@random}")
      File.mkdir_p!(path)
      on_exit(fn -> File.rm_rf!(path) end)
      {:ok, path: path}
    end

    test "adds ectomancer dependency to empty deps", %{path: path} do
      mix_path = Path.join(path, "mix.exs")
      
      # Create minimal mix.exs
      content = """
      defmodule Test.MixProject do
        use Mix.Project

        def project do
          [
            app: :test,
            version: "1.0.0"
          ]
        end

        def application do
          [applications: [:logger]]
        end
      end
      """
      File.write!(mix_path, content)

      result = ConfigUpdater.update_mix_exs(mix_path)
      
      assert {:ok, _} = result
      assert File.exists?(mix_path)
      assert String.contains?(File.read!(mix_path), "{:ectomancer,")
    end

    test "returns not_modified when already added", %{path: path} do
      mix_path = Path.join(path, "mix.exs")
      
      # Create mix.exs with ectomancer already present
      content = """
      defmodule Test.MixProject do
        use Mix.Project

        def project do
          [
            app: :test,
            version: "1.0.0",
            deps: [
              {:ecto, "~> 3.12"},
              {:ectomancer, "~> 1.0"}
            ]
          ]
        end

        def application do
          [applications: [:logger]]
        end
      end
      """
      File.write!(mix_path, content)

      result = ConfigUpdater.update_mix_exs(mix_path)
      assert :not_modified = result
    end

    test "returns error for non-existent file", %{path: path} do
      mix_path = Path.join(path, "nonexistent.exs")
      result = ConfigUpdater.update_mix_exs(mix_path)
      assert :error = result
    end
  end

  describe "update_config_exs/1" do
    setup do
      # Create a temp directory for testing
      path = System.tmp_dir!() |> Path.join("test_config_#{@random}")
      File.mkdir_p!(Path.join(path, "config"))
      on_exit(fn -> File.rm_rf!(path) end)
      {:ok, path: path}
    end

    test "adds ectomancer config to empty config", %{path: path} do
      config_path = Path.join(path, "config", "config.exs")
      
      # Create minimal config.exs
      content = """
      import Config
      """
      File.write!(config_path, content)

      result = ConfigUpdater.update_config_exs(config_path)
      
      assert {:ok, _} = result
      assert String.contains?(File.read!(config_path), "config :ectomancer")
    end

    test "returns not_modified when already configured", %{path: path} do
      config_path = Path.join(path, "config", "config.exs")
      
      # Create config.exs with ectomancer already present
      content = """
      import Config

      config :ectomancer,
        repo: MyApp.Repo
      """
      File.write!(config_path, content)

      result = ConfigUpdater.update_config_exs(config_path)
      assert :not_modified = result
    end

    test "returns error for non-existent file", %{path: path} do
      config_path = Path.join(path, "config", "nonexistent.exs")
      result = ConfigUpdater.update_config_exs(config_path)
      assert :error = result
    end
  end

  describe "update_router_exs/1" do
    setup do
      # Create a temp directory for testing
      path = System.tmp_dir!() |> Path.join("test_router_#{@random}")
      File.mkdir_p!(path)
      on_exit(fn -> File.rm_rf!(path) end)
      {:ok, path: path}
    end

    test "adds ectomancer route to empty router", %{path: path} do
      router_path = Path.join(path, "router.ex")
      
      # Create minimal router
      content = """
      defmodule TestWeb.Router do
        use Phoenix.Router
      end
      """
      File.write!(router_path, content)

      result = ConfigUpdater.update_router_exs(router_path)
      
      assert {:ok, _} = result
      assert String.contains?(File.read!(router_path), "forward \"/mcp\", Ectomancer.Plug")
    end

    test "returns not_modified when already has route", %{path: path} do
      router_path = Path.join(path, "router.ex")
      
      # Create router with ectomancer already present
      content = """
      defmodule TestWeb.Router do
        use Phoenix.Router

        forward "/mcp", Ectomancer.Plug
      end
      """
      File.write!(router_path, content)

      result = ConfigUpdater.update_router_exs(router_path)
      assert :not_modified = result
    end

    test "returns error for non-existent file", %{path: path} do
      router_path = Path.join(path, "nonexistent.ex")
      result = ConfigUpdater.update_router_exs(router_path)
      assert :error = result
    end
  end

  describe "update_files/1" do
    test "updates all three files and returns status map", %{path: path: path} do
      # Setup test files
      mix_path = Path.join(path, "mix.exs")
      config_path = Path.join(path, "config", "config.exs")
      router_path = Path.join(path, "router.ex")

      File.mkdir_p!(Path.join(path, "config"))
      
      File.write!(mix_path, """
      defmodule Test.MixProject do
        use Mix.Project
        def project do([app: :test]); end
        def application do([applications: [:logger]]); end
      end
      """)
      
      File.write!(config_path, "import Config\n")
      File.write!(router_path, "defmodule TestWeb.Router do\n  use Phoenix.Router\nend\n")

      result = ConfigUpdater.update_files([
        mix_path: mix_path,
        config_path: config_path,
        router_path: router_path
      ])

      assert is_map(result)
      assert Map.has_key?(result, :mix_exs)
      assert Map.has_key?(result, :config_exs)
      assert Map.has_key?(result, :router_exs)
      
      # All should have been updated
      assert {:ok, _} = result.mix_exs
      assert {:ok, _} = result.config_exs
      assert {:ok, _} = result.router_exs
    end
  end
end
