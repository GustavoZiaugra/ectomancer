defmodule Mix.Tasks.Ectomancer.Setup do
  @moduledoc """
  Interactive setup tool for Ectomancer.

  This Mix task provides an interactive workflow to configure Ectomancer in
  your Phoenix/Ecto project. It automatically discovers Ecto schemas, generates
  the necessary configuration, and updates your project files.

  ## Usage

      mix ectomancer.setup

  ## Workflow

  1. Checks for required dependencies (ecto, plug)
  2. Scans for Ecto schemas in the project
  3. Prompts user to select which schemas to expose
  4. Asks about optional features (Oban bridge, custom namespace)
  5. Generates MCP module and updates configuration files
  6. Provides next steps for the user

  ## Examples

      $ mix ectomancer.setup
      🔍 Scanning for Ecto schemas...
      Found 3 schemas:
        ✓ MyApp.Accounts.User
        ✓ MyApp.Blog.Post
        ✓ MyApp.Blog.Comment

      ? Select schemas to expose (comma-separated numbers, e.g., 1,2,3)
      > 1,2
      ? Include Oban bridge? (y/N)
      > n
      ? Tool namespace? (e.g., 'MyApp', leave empty for none)
      >

  ## Return Codes

  - `0` - Success
  - `1` - No schemas found or no schemas selected
  - `2` - File generation error
  - `3` - Missing required dependencies
  """

  use Mix.Task

  alias Ectomancer.Installer.ConfigUpdater
  alias Ectomancer.Installer.DependencyChecker
  alias Ectomancer.Installer.SchemaDiscovery
  alias Ectomancer.Installer.TemplateRenderer

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile")
    Mix.shell().info("\n🚀 Setting up Ectomancer...")

    app_name = detect_app_name()

    check_dependencies!()
    schemas = discover_schemas!()
    selected_schemas = select_schemas!(schemas)

    optional_deps = DependencyChecker.check_optional()
    include_oban = if :oban in optional_deps, do: prompt_for_oban_bridge(), else: false
    namespace = prompt_for_namespace()

    mcp_path = generate_mcp_module(selected_schemas, include_oban, namespace, app_name)
    update_configuration_files(app_name)
    print_summary(selected_schemas, include_oban, namespace, mcp_path)

    :ok
  end

  defp check_dependencies! do
    case DependencyChecker.check_required() do
      :ok ->
        Mix.shell().info("   ✓ Required dependencies found")

      {:error, missing} ->
        Mix.shell().error("\n❌ Missing required dependencies!")
        Mix.shell().error(DependencyChecker.missing_deps_message(missing))
        Mix.shell().info("   Exiting...")
        exit({:shutdown, 3})
    end
  end

  defp discover_schemas! do
    Mix.shell().info("\n🔍 Scanning for Ecto schemas...")
    schemas = SchemaDiscovery.discover()

    unless Enum.any?(schemas) do
      Mix.shell().error("\n❌ No Ecto schemas found!")

      Mix.shell().error(
        "   Make sure you have Ecto schemas with 'use Ecto.Schema' in your project."
      )

      Mix.shell().info("   Exiting...")
      exit({:shutdown, 1})
    end

    Mix.shell().info("\n📦 Found #{length(schemas)} schema(s):")

    Enum.each(schemas, fn schema ->
      Mix.shell().info("   ✓ #{inspect(schema.module)}")
    end)

    schemas
  end

  defp select_schemas!(schemas) do
    selected_schemas = prompt_for_schema_selection(schemas)

    if selected_schemas == [] do
      Mix.shell().error("\n❌ No schemas selected!")
      Mix.shell().info("   Exiting...")
      exit({:shutdown, 1})
    end

    selected_schemas
  end

  defp generate_mcp_module(selected_schemas, include_oban, namespace, app_name) do
    Mix.shell().info("\n📝 Generating MCP module...")

    mcp_path = get_mcp_module_path(app_name)
    module_name = mcp_module_name(app_name)

    case TemplateRenderer.generate_mcp_module(
           schemas: selected_schemas,
           output_path: mcp_path,
           include_oban: include_oban,
           namespace: namespace,
           module_name: module_name
         ) do
      {:ok, message} ->
        Mix.shell().info("   ✓ #{message}")

      :not_modified ->
        Mix.shell().info("   ℹ️  MCP module already exists and is up to date")
    end

    mcp_path
  end

  defp update_configuration_files(app_name) do
    Mix.shell().info("\n⚙️  Updating configuration files...")

    config = [
      mix_path: "mix.exs",
      config_path: "config/config.exs",
      router_path: find_router_path(app_name)
    ]

    results = ConfigUpdater.update_files(config)
    print_config_update_results(results)
  end

  defp print_summary(selected_schemas, include_oban, namespace, mcp_path) do
    tool_count = count_tools(selected_schemas)

    Mix.shell().info("\n✅ Setup complete!")
    Mix.shell().info("\n📋 Summary:")
    Mix.shell().info("   • Added #{length(selected_schemas)} schema(s)")
    Mix.shell().info("   • Generated #{tool_count} tool(s)")
    Mix.shell().info("   • Oban bridge: #{if include_oban, do: "enabled", else: "disabled"}")
    Mix.shell().info("   • Namespace: #{namespace || "none"}")
    Mix.shell().info("   • MCP module: #{Path.basename(mcp_path)}")

    Mix.shell().info("\n📝 Next steps:")
    Mix.shell().info("   1. Run: mix deps.get")
    Mix.shell().info("   2. Start server: mix phx.server")
    Mix.shell().info("   3. Test at: http://localhost:4000/mcp")

    Mix.shell().info("\n💡 Tip: You can modify #{mcp_path} to customize the exposed schemas.")
  end

  defp print_config_update_results(results) do
    Enum.each(results, fn {file, result} ->
      case result do
        {:ok, message} -> Mix.shell().info("   ✓ #{message}")
        :not_modified -> Mix.shell().info("   ℹ️  #{file} already up to date")
        :error -> Mix.shell().error("   ❌ Failed to update #{file}")
        nil -> :ok
      end
    end)
  end

  defp prompt_for_schema_selection(schemas) do
    schemas
    |> Enum.with_index(1)
    |> Enum.each(fn {schema, index} ->
      Mix.shell().info("   [#{index}] #{inspect(schema.module)}")
    end)

    Mix.shell().info("")

    selections = prompt_for_selections(schemas)

    Enum.map(selections, fn index ->
      Enum.at(schemas, index)
    end)
  end

  defp prompt_for_selections(schemas) do
    Mix.shell().info("? Select schemas to expose (comma-separated numbers, e.g., 1,2,3)")

    input = get_input()

    input
    |> String.trim()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.map(&parse_selection/1)
    |> Enum.filter(&(&1 != nil))
    |> Enum.uniq()
    |> Enum.filter(fn index ->
      index >= 0 and index < length(schemas)
    end)
  end

  defp parse_selection(input) do
    case Integer.parse(input) do
      {num, ""} -> num - 1
      _ -> nil
    end
  end

  defp prompt_for_oban_bridge do
    Mix.shell().info("? Include Oban bridge? (y/N)")

    input = get_input() |> String.downcase() |> String.trim()

    case input do
      input when input in ["y", "yes"] -> true
      _ -> false
    end
  end

  defp prompt_for_namespace do
    Mix.shell().info("? Tool namespace? (e.g., 'MyApp', leave empty for none)")

    case get_input() |> String.trim() do
      "" -> nil
      value -> value
    end
  end

  defp get_input do
    case IO.gets("> ") do
      :eof -> ""
      {:error, _} -> ""
      input -> input
    end
  end

  defp count_tools(schemas) do
    Enum.reduce(schemas, 0, fn schema, acc ->
      if Enum.any?(schema.writable_fields), do: acc + 5, else: acc + 2
    end)
  end

  defp get_mcp_module_path(app_name) do
    "lib/#{app_name || "my_app"}/mcp.ex"
  end

  defp mcp_module_name(app_name) do
    case app_name do
      nil -> "MyApp.MCP"
      name -> "#{Macro.camelize(name)}.MCP"
    end
  end

  defp detect_app_name do
    case File.read("mix.exs") do
      {:ok, content} ->
        case Regex.run(~r/app:\s*:(\w+)/, content) do
          [_, app_name] -> app_name
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp find_router_path(app_name) do
    if app_name do
      [
        "lib/#{app_name}_web/router.ex",
        "lib/#{app_name}/router.ex"
      ]
    else
      []
    end
    |> Enum.find(&File.exists?/1)
  end
end
