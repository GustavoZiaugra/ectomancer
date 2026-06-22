defmodule Mix.Tasks.Ectomancer.TeardownTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Ectomancer.Teardown

  describe "run/1" do
    test "exits gracefully when nothing to clean up" do
      in_tmp(fn ->
        File.write!("mix.exs", ~s(defmodule Dummy.MixProject do
  use Mix.Project
  def project do
    [app: :dummy, version: "0.1.0"]
  end
end))
        File.mkdir_p!("config")
        File.write!("config/config.exs", "import Config\n")

        assert catch_exit(Teardown.run([])) == {:shutdown, 1}
      end)
    end
  end

  describe "detect_app_name/0" do
    test "reads app name from mix.exs" do
      in_tmp(fn ->
        File.write!("mix.exs", ~s(defmodule Dummy.MixProject do
  use Mix.Project
  def project do
    [app: :dummy, version: "0.1.0"]
  end
end))
        assert Teardown.detect_app_name() == "dummy"
      end)
    end

    test "returns nil when no mix.exs" do
      in_tmp(fn ->
        assert Teardown.detect_app_name() == nil
      end)
    end

    test "returns nil when app not parseable" do
      in_tmp(fn ->
        File.write!("mix.exs", "invalid elixir file")
        assert Teardown.detect_app_name() == nil
      end)
    end
  end

  describe "anything_to_cleanup?/1" do
    test "returns false when nothing installed" do
      in_tmp(fn ->
        File.write!("mix.exs", ~s(defmodule Dummy.MixProject do
  use Mix.Project
  def project do
    [app: :dummy, version: "0.1.0"]
  end
end))
        File.mkdir_p!("config")
        File.write!("config/config.exs", "import Config\n")

        refute Teardown.anything_to_cleanup?("dummy")
      end)
    end

    test "returns true when mcp module exists" do
      in_tmp(fn ->
        File.write!("mix.exs", ~s(defmodule Dummy.MixProject do
  use Mix.Project
  def project do
    [app: :dummy, version: "0.1.0"]
  end
end))
        File.mkdir_p!("lib/dummy")
        File.write!("lib/dummy/mcp.ex", "# mcp module")

        assert Teardown.anything_to_cleanup?("dummy")
      end)
    end
  end

  describe "has_dependency?/0" do
    test "returns true when ectomancer in deps" do
      in_tmp(fn ->
        File.write!("mix.exs", ~s(defmodule Dummy.MixProject do
  use Mix.Project
  def project do
    [app: :dummy, deps: [{:ectomancer, "~> 1.0"}]]
  end
end))
        assert Teardown.has_dependency?()
      end)
    end

    test "returns false when no ectomancer dep" do
      in_tmp(fn ->
        File.write!("mix.exs", ~s(defmodule Dummy.MixProject do
  use Mix.Project
  def project do
    [app: :dummy]
  end
end))
        refute Teardown.has_dependency?()
      end)
    end

    test "returns false when no mix.exs" do
      in_tmp(fn ->
        refute Teardown.has_dependency?()
      end)
    end
  end

  describe "has_config?/0" do
    test "returns true when ectomancer config exists" do
      in_tmp(fn ->
        File.mkdir_p!("config")

        File.write!("config/config.exs", """
        import Config
        config :ectomancer, repo: Dummy.Repo
        """)

        assert Teardown.has_config?()
      end)
    end

    test "returns false when no ectomancer config" do
      in_tmp(fn ->
        File.mkdir_p!("config")
        File.write!("config/config.exs", "import Config\n")

        refute Teardown.has_config?()
      end)
    end

    test "returns false when no config file" do
      in_tmp(fn ->
        refute Teardown.has_config?()
      end)
    end
  end

  describe "has_route?/1" do
    test "returns true when Ectomancer.Plug route exists" do
      in_tmp(fn ->
        File.write!("router.ex", "forward \"/mcp\", Ectomancer.Plug\n")

        assert Teardown.has_route?("router.ex")
      end)
    end

    test "returns false when no Ectomancer.Plug route" do
      in_tmp(fn ->
        File.write!("router.ex", "forward \"/api\", Api.Plug\n")

        refute Teardown.has_route?("router.ex")
      end)
    end

    test "returns false when router file missing" do
      in_tmp(fn ->
        refute Teardown.has_route?("missing.ex")
      end)
    end
  end

  describe "remove_mix_dependency_content/1" do
    test "removes ectomancer dep from file" do
      in_tmp(fn ->
        content = """
        defmodule Dummy.MixProject do
          use Mix.Project
          def project do
            [
              app: :dummy,
              deps: [
                {:ecto, "~> 3.0"},
                {:ectomancer, "~> 1.0"},
                {:phoenix, "~> 1.7"}
              ]
            ]
          end
        end
        """

        File.write!("mix.exs", content)

        assert {:ok, _message} = Teardown.remove_mix_dependency_content(content)

        updated = File.read!("mix.exs")
        refute String.contains?(updated, "{:ectomancer,")
        assert String.contains?(updated, "{:ecto,")
      end)
    end

    test "returns error when no ectomancer dep" do
      in_tmp(fn ->
        content = "defmodule Dummy.MixProject do\nend"
        File.write!("mix.exs", content)

        assert Teardown.remove_mix_dependency_content(content) == :error
      end)
    end
  end

  describe "remove_ectomancer_config_content/2" do
    test "removes ectomancer config from file" do
      in_tmp(fn ->
        path = "config/config.exs"
        File.mkdir_p!("config")

        content = """
        import Config

        # Ectomancer MCP Server Configuration
        config :ectomancer,
          repo: Dummy.Repo

        config :dummy, :other, true
        """

        File.write!(path, content)

        assert {:ok, _message} = Teardown.remove_ectomancer_config_content(path, content)

        updated = File.read!(path)
        refute String.contains?(updated, "config :ectomancer,")
        assert String.contains?(updated, "config :dummy, :other")
      end)
    end

    test "returns error when no ectomancer config" do
      in_tmp(fn ->
        path = "config/config.exs"
        File.mkdir_p!("config")
        content = "import Config\nconfig :dummy, :key, :value\n"
        File.write!(path, content)

        assert Teardown.remove_ectomancer_config_content(path, content) == :error
      end)
    end
  end

  describe "remove_router_route_content/2" do
    test "removes Ectomancer.Plug route from file" do
      in_tmp(fn ->
        path = "router.ex"

        content = """
        defmodule DummyWeb.Router do
          use Plug.Router

          # Ectomancer MCP
          forward "/mcp", Ectomancer.Plug

          forward "/api", Api.Plug
        end
        """

        File.write!(path, content)

        assert {:ok, _message} = Teardown.remove_router_route_content(path, content)

        updated = File.read!(path)
        refute String.contains?(updated, "Ectomancer.Plug")
        assert String.contains?(updated, "Api.Plug")
      end)
    end

    test "returns error when no Ectomancer route" do
      in_tmp(fn ->
        path = "router.ex"
        content = "defmodule DummyWeb.Router do\n  forward \"/api\", Api.Plug\nend\n"
        File.write!(path, content)

        assert Teardown.remove_router_route_content(path, content) == :error
      end)
    end
  end

  describe "dir_empty?/1" do
    test "returns true for empty directory" do
      in_tmp(fn ->
        File.mkdir_p!("empty_dir")
        assert Teardown.dir_empty?("empty_dir")
      end)
    end

    test "returns false for non-empty directory" do
      in_tmp(fn ->
        File.mkdir_p!("nonempty_dir")
        File.write!("nonempty_dir/file.txt", "content")
        refute Teardown.dir_empty?("nonempty_dir")
      end)
    end
  end

  describe "mcp_module_path/1" do
    test "builds path for given app name" do
      assert Teardown.mcp_module_path("my_app") == "lib/my_app/mcp.ex"
    end

    test "uses my_app fallback when nil" do
      assert Teardown.mcp_module_path(nil) == "lib/my_app/mcp.ex"
    end
  end

  describe "router_path/1" do
    test "returns nil when app_name is nil" do
      assert Teardown.router_path(nil) == nil
    end

    test "finds existing router file" do
      in_tmp(fn ->
        File.mkdir_p!("lib/my_app_web")
        File.write!("lib/my_app_web/router.ex", "# router")

        assert Teardown.router_path("my_app") == "lib/my_app_web/router.ex"
      end)
    end

    test "returns nil when no router files exist" do
      in_tmp(fn ->
        assert Teardown.router_path("my_app") == nil
      end)
    end
  end

  describe "print_results/1" do
    setup do
      original_shell = Mix.shell()
      Mix.shell(Mix.Shell.Process)

      on_exit(fn ->
        Mix.shell(original_shell)
      end)

      :ok
    end

    test "prints summary of all result types" do
      results = [
        mcp_module: {:ok, "Removed lib/my_app/mcp.ex"},
        mix_exs: {:ok, "Removed Ectomancer dependency"},
        config_exs: :not_found,
        router_exs: :error
      ]

      Teardown.print_results(results)
      # Should not crash
      assert true
    end

    test "handles successful results only" do
      results = [file_a: {:ok, "Removed a"}, file_b: {:ok, "Removed b"}]
      Teardown.print_results(results)
      assert true
    end
  end

  defp in_tmp(fun) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ectomancer_teardown_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    File.cd!(dir, fn ->
      try do
        fun.()
      after
        File.rm_rf!(dir)
      end
    end)
  end
end
