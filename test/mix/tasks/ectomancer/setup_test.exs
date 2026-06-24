defmodule Mix.Tasks.Ectomancer.SetupTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Ectomancer.Setup

  setup do
    original_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(original_shell)
    end)

    :ok
  end

  describe "run/1" do
    test "exits gracefully when no schemas found in empty project" do
      in_tmp(fn ->
        File.write!("mix.exs", ~s(defmodule Dummy.MixProject do
  use Mix.Project
  def project do
    [
      app: :dummy,
      version: "0.1.0",
      deps: [{:ecto, "~> 3.0"}, {:plug, "~> 1.0"}]
    ]
  end
end))

        File.mkdir_p!("lib/dummy")
        File.mkdir_p!("config")
        File.write!("config/config.exs", "import Config\n")

        assert catch_exit(Setup.run([])) == {:shutdown, 1}
      end)
    end

    test "exits when required dependencies are missing" do
      in_tmp(fn ->
        File.write!("mix.exs", ~s(defmodule Dummy.MixProject do
  use Mix.Project
  def project do
    [
      app: :dummy,
      version: "0.1.0",
      deps: []
    ]
  end
end))

        File.mkdir_p!("lib/dummy")
        File.mkdir_p!("config")
        File.write!("config/config.exs", "import Config\n")

        assert catch_exit(Setup.run([])) == {:shutdown, 3}
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
        assert Setup.detect_app_name() == "my_app"
      end)
    end

    test "returns nil when no mix.exs" do
      in_tmp(fn ->
        assert Setup.detect_app_name() == nil
      end)
    end

    test "returns nil when app not parseable" do
      in_tmp(fn ->
        File.write!("mix.exs", "not valid")
        assert Setup.detect_app_name() == nil
      end)
    end
  end

  describe "count_tools/1" do
    test "counts 5 tools per schema with writable fields" do
      schema = %{writable_fields: [:email, :name]}
      assert Setup.count_tools([schema]) == 5
    end

    test "counts 2 tools per schema without writable fields" do
      schema = %{writable_fields: []}
      assert Setup.count_tools([schema]) == 2
    end

    test "sums across multiple schemas" do
      writable = %{writable_fields: [:email]}
      read_only = %{writable_fields: []}

      assert Setup.count_tools([writable, read_only]) == 7
    end
  end

  describe "mcp_module_name/1" do
    test "returns default when name is nil" do
      assert Setup.mcp_module_name(nil) == "MyApp.MCP"
    end

    test "builds module name from app name" do
      assert Setup.mcp_module_name("my_app") == "MyApp.MCP"
      assert Setup.mcp_module_name("blog") == "Blog.MCP"
    end
  end

  describe "get_mcp_module_path/1" do
    test "builds path for given app name" do
      assert Setup.get_mcp_module_path("my_app") == "lib/my_app/mcp.ex"
    end

    test "uses fallback when nil" do
      assert Setup.get_mcp_module_path(nil) == "lib/my_app/mcp.ex"
    end
  end

  describe "find_router_path/1" do
    test "returns nil when app_name is nil" do
      assert Setup.find_router_path(nil) == nil
    end

    test "finds router in _web suffix" do
      in_tmp(fn ->
        File.mkdir_p!("lib/my_app_web")
        File.write!("lib/my_app_web/router.ex", "# router")

        assert Setup.find_router_path("my_app") == "lib/my_app_web/router.ex"
      end)
    end

    test "finds router without _web suffix" do
      in_tmp(fn ->
        File.mkdir_p!("lib/my_app")
        File.write!("lib/my_app/router.ex", "# router")

        assert Setup.find_router_path("my_app") == "lib/my_app/router.ex"
      end)
    end

    test "returns nil when no router found" do
      in_tmp(fn ->
        assert Setup.find_router_path("my_app") == nil
      end)
    end
  end

  describe "parse_selection/1" do
    test "parses integer input (1-indexed → 0-indexed)" do
      assert Setup.parse_selection("1") == 0
      assert Setup.parse_selection("3") == 2
    end

    test "returns nil for non-integer input" do
      assert Setup.parse_selection("abc") == nil
      assert Setup.parse_selection("1.5") == nil
      assert Setup.parse_selection("") == nil
    end
  end

  describe "print_summary/4" do
    setup do
      original_shell = Mix.shell()
      Mix.shell(Mix.Shell.Process)

      on_exit(fn ->
        Mix.shell(original_shell)
      end)

      :ok
    end

    test "prints summary with schemas" do
      schema = %{writable_fields: [:email]}
      Setup.print_summary([schema], false, nil, "lib/test/mcp.ex")

      assert_received {:mix_shell, :info, [msg]}
      assert msg =~ "Setup complete"
    end

    test "prints summary with oban bridge and namespace" do
      schema = %{writable_fields: [:email, :name]}

      Setup.print_summary([schema], true, "admin", "lib/my_app/mcp.ex")

      assert_received {:mix_shell, :info, [msg]}
      assert msg =~ "Setup complete"
    end
  end

  describe "print_config_update_results/1" do
    setup do
      original_shell = Mix.shell()
      Mix.shell(Mix.Shell.Process)

      on_exit(fn ->
        Mix.shell(original_shell)
      end)

      :ok
    end

    test "prints results for :ok, :not_modified, and :error" do
      results = [
        mix_exs: {:ok, "Updated mix.exs"},
        config: :not_modified,
        router: :error
      ]

      Setup.print_config_update_results(results)
      # Should not crash — just verify it runs
      assert true
    end

    test "handles nil results" do
      Setup.print_config_update_results(file_a: nil)
      assert true
    end
  end

  defp in_tmp(fun) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ectomancer_setup_test_#{System.unique_integer([:positive])}"
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
