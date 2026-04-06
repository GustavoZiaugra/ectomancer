defmodule Ectomancer.Installer.ConfigUpdaterTest do
  use ExUnit.Case, async: true
  alias Ectomancer.Installer.ConfigUpdater

  # Helper to create unique temp directories
  defp temp_dir(prefix) do
    random = System.unique_integer([:positive])
    path = System.tmp_dir!() |> Path.join("#{prefix}_#{random}")
    File.mkdir_p!(path)
    path
  end

  describe "update_mix_exs/1" do
    test "adds ectomancer dependency to mix.exs" do
      path = temp_dir("test_mix")
      on_exit(fn -> File.rm_rf!(path) end)

      mix_path = Path.join(path, "mix.exs")

      # Create minimal mix.exs
      content = """
      defmodule Test.MixProject do
        use Mix.Project

        def project do
          [
            app: :test,
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
      """

      File.write!(mix_path, content)

      result = ConfigUpdater.update_mix_exs(mix_path)

      assert {:ok, _} = result
      assert File.exists?(mix_path)
      assert String.contains?(File.read!(mix_path), "{:ectomancer,")

      File.rm_rf!(path)
    end

    test "returns not_modified when already added" do
      path = temp_dir("test_mix")
      on_exit(fn -> File.rm_rf!(path) end)

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

      File.rm_rf!(path)
    end

    test "returns error for non-existent file" do
      path = temp_dir("test_mix")
      on_exit(fn -> File.rm_rf!(path) end)

      mix_path = Path.join(path, "nonexistent.exs")
      result = ConfigUpdater.update_mix_exs(mix_path)
      assert :error = result

      File.rm_rf!(path)
    end
  end

  describe "update_config_exs/1" do
    test "adds ectomancer config to config.exs" do
      path = temp_dir("test_config")
      on_exit(fn -> File.rm_rf!(path) end)

      File.mkdir_p!(Path.join(path, "config"))
      config_path = Path.join([path, "config", "config.exs"])

      # Create minimal config.exs
      content = """
      import Config
      """

      File.write!(config_path, content)

      result = ConfigUpdater.update_config_exs(config_path)

      assert {:ok, _} = result
      assert String.contains?(File.read!(config_path), "config :ectomancer")

      File.rm_rf!(path)
    end

    test "returns not_modified when already configured" do
      path = temp_dir("test_config")
      on_exit(fn -> File.rm_rf!(path) end)

      File.mkdir_p!(Path.join(path, "config"))
      config_path = Path.join([path, "config", "config.exs"])

      # Create config.exs with ectomancer already present
      content = """
      import Config

      config :ectomancer,
        repo: MyApp.Repo
      """

      File.write!(config_path, content)

      result = ConfigUpdater.update_config_exs(config_path)
      assert :not_modified = result

      File.rm_rf!(path)
    end

    test "returns error for non-existent file" do
      path = temp_dir("test_config")
      on_exit(fn -> File.rm_rf!(path) end)

      config_path = Path.join([path, "config", "nonexistent.exs"])
      result = ConfigUpdater.update_config_exs(config_path)
      assert :error = result

      File.rm_rf!(path)
    end
  end

  describe "update_router_exs/1" do
    test "adds ectomancer route to router" do
      path = temp_dir("test_router")
      on_exit(fn -> File.rm_rf!(path) end)

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

      File.rm_rf!(path)
    end

    test "returns not_modified when already has route" do
      path = temp_dir("test_router")
      on_exit(fn -> File.rm_rf!(path) end)

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

      File.rm_rf!(path)
    end

    test "returns error for non-existent file" do
      path = temp_dir("test_router")
      on_exit(fn -> File.rm_rf!(path) end)

      router_path = Path.join(path, "nonexistent.ex")
      result = ConfigUpdater.update_router_exs(router_path)
      assert :error = result

      File.rm_rf!(path)
    end
  end

  describe "update_files/1" do
    test "updates all three files and returns status map" do
      path = temp_dir("test_all")
      on_exit(fn -> File.rm_rf!(path) end)

      # Setup test files
      mix_path = Path.join(path, "mix.exs")
      config_path = Path.join([path, "config", "config.exs"])
      router_path = Path.join(path, "router.ex")

      File.mkdir_p!(Path.join(path, "config"))

      File.write!(mix_path, """
      defmodule Test.MixProject do
        use Mix.Project
        
        def project do
          [
            app: :test,
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

      File.write!(config_path, "import Config\n")

      File.write!(router_path, """
      defmodule TestWeb.Router do
        use Phoenix.Router
      end
      """)

      result =
        ConfigUpdater.update_files(
          mix_path: mix_path,
          config_path: config_path,
          router_path: router_path
        )

      assert is_map(result)
      assert Map.has_key?(result, :mix_exs)
      assert Map.has_key?(result, :config_exs)
      assert Map.has_key?(result, :router_exs)

      # All should have been updated
      assert {:ok, _} = result.mix_exs
      assert {:ok, _} = result.config_exs
      assert {:ok, _} = result.router_exs

      File.rm_rf!(path)
    end
  end
end
