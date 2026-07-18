defmodule Ectomancer.IgniterTest do
  use ExUnit.Case, async: false

  alias Ectomancer.Igniter

  setup do
    original_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(original_shell)
    end)

    :ok
  end

  describe "install/2" do
    test "raises when required dependencies are missing" do
      in_tmp(fn ->
        File.write!("mix.exs", ~s(defmodule Dummy.MixProject do
  use Mix.Project
  def project do
    [app: :dummy, version: "0.1.0", deps: []]
  end
end))

        File.mkdir_p!("config")
        File.write!("config/config.exs", "import Config\n")

        igniter = build_igniter()

        assert_raise Mix.Error, ~r/missing required dependencies/i, fn ->
          Igniter.install(igniter, [])
        end
      end)
    end

    test "raises when no schemas found" do
      in_tmp(fn ->
        File.write!("mix.exs", ~s(defmodule Dummy.MixProject do
  use Mix.Project
  def project do
    [app: :dummy, version: "0.1.0", deps: [{:ecto, "~> 3.0"}, {:plug, "~> 1.0"}]]
  end
end))

        File.mkdir_p!("config")
        File.write!("config/config.exs", "import Config\n")
        File.mkdir_p!("lib")

        igniter = build_igniter()

        assert_raise Mix.Error, ~r/no Ecto schemas found/i, fn ->
          Igniter.install(igniter, [])
        end
      end)
    end
  end

  describe "detect_app_name/0" do
    test "reads app name from mix.exs" do
      in_tmp(fn ->
        File.write!("mix.exs", ~s(defmodule Dummy.MixProject do
  use Mix.Project
  def project do
    [app: :my_app, version: "0.1.0"]
  end
end))
        assert Igniter.detect_app_name() == "my_app"
      end)
    end

    test "returns nil when no mix.exs" do
      in_tmp(fn ->
        assert Igniter.detect_app_name() == nil
      end)
    end

    test "returns nil when app not parseable" do
      in_tmp(fn ->
        File.write!("mix.exs", "not valid")
        assert Igniter.detect_app_name() == nil
      end)
    end
  end

  describe "mcp_module_name/1" do
    test "returns default when name is nil" do
      assert Igniter.mcp_module_name(nil) == "MyApp.MCP"
    end

    test "builds module name from app name" do
      assert Igniter.mcp_module_name("my_app") == "MyApp.MCP"
      assert Igniter.mcp_module_name("blog") == "Blog.MCP"
    end
  end

  describe "get_mcp_module_path/1" do
    test "builds path for given app name" do
      assert Igniter.get_mcp_module_path("my_app") == "lib/my_app/mcp.ex"
    end

    test "uses fallback when nil" do
      assert Igniter.get_mcp_module_path(nil) == "lib/my_app/mcp.ex"
    end
  end

  describe "find_router_path/1" do
    test "returns nil when app_name is nil" do
      assert Igniter.find_router_path(nil) == nil
    end

    test "finds router in _web suffix" do
      in_tmp(fn ->
        File.mkdir_p!("lib/my_app_web")
        File.write!("lib/my_app_web/router.ex", "# router")
        assert Igniter.find_router_path("my_app") == "lib/my_app_web/router.ex"
      end)
    end

    test "finds router without _web suffix" do
      in_tmp(fn ->
        File.mkdir_p!("lib/my_app")
        File.write!("lib/my_app/router.ex", "# router")
        assert Igniter.find_router_path("my_app") == "lib/my_app/router.ex"
      end)
    end

    test "returns nil when no router found" do
      in_tmp(fn ->
        assert Igniter.find_router_path("my_app") == nil
      end)
    end
  end

  describe "print_config_update_results/1" do
    test "handles ok results" do
      Igniter.print_config_update_results(config_exs: {:ok, "Added config"})
      assert_received {:mix_shell, :info, [msg]}
      assert msg =~ "Added config"
    end

    test "handles not_modified results" do
      Igniter.print_config_update_results(config_exs: :not_modified)
      assert_received {:mix_shell, :info, [msg]}
      assert msg =~ "already up to date"
    end

    test "handles error results" do
      Igniter.print_config_update_results(config_exs: :error)
      assert_received {:mix_shell, :error, [msg]}
      assert msg =~ "Failed to update"
    end

    test "handles nil results" do
      Igniter.print_config_update_results(router_exs: nil)
      assert true
    end
  end

  defp build_igniter do
    igniter_mod = Module.concat(["Igniter"])

    if Code.ensure_loaded?(igniter_mod) do
      struct(igniter_mod)
    else
      %{}
    end
  end

  defp in_tmp(fun) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ectomancer_igniter_test_#{System.unique_integer([:positive])}"
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
