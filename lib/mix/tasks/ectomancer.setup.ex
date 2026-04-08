defmodule Ectomancer.Mix.Tasks.Ectomancer.Setup do
  @moduledoc """
  Interactive setup tool for Ectomancer.

  This Mix task provides an interactive workflow to configure Ectomancer in
  your Phoenix/Ecto project. It automatically discovers Ecto schemas, generates
  the necessary configuration, and updates your project files.

  ## Usage

      mix ectomancer.setup

  ## Workflow

  1. Scans for Ecto schemas in the project
  2. Prompts user to select which schemas to expose
  3. Asks about optional features (Oban bridge, custom namespace)
  4. Generates MCP module and updates configuration files
  5. Provides next steps for the user

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
  """

  use Mix.Task

  alias Ectomancer.Installer.SchemaDiscovery
  alias Ectomancer.Installer.TemplateRenderer
  alias Ectomancer.Installer.ConfigUpdater

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("\n🚀 Setting up Ectomancer...")

    # Step 1: Discover schemas
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

    # Display schemas
    Enum.each(schemas, fn schema ->
      Mix.shell().info("   ✓ #{inspect(schema.module)}")
    end)

    # Step 2: Get user selections
    selected_schemas = prompt_for_schema_selection(schemas)

    unless length(selected_schemas) > 0 do
      Mix.shell().error("\n❌ No schemas selected!")
      Mix.shell().info("   Exiting...")
      exit({:shutdown, 1})
    end

    # Step 3: Get optional configurations
    include_oban = prompt_for_oban_bridge()
    namespace = prompt_for_namespace()

    # Step 4: Generate MCP module
    Mix.shell().info("\n📝 Generating MCP module...")

    mcp_path = get_mcp_module_path()

    case TemplateRenderer.generate_mcp_module(
           schemas: selected_schemas,
           output_path: mcp_path,
           include_oban: include_oban,
           namespace: namespace
         ) do
      {:ok, message} ->
        Mix.shell().info("   ✓ #{message}")

      :not_modified ->
        Mix.shell().info("   ℹ️  MCP module already exists and is up to date")
    end

    # Step 5: Update configuration files
    Mix.shell().info("\n⚙️  Updating configuration files...")

    config = %{
      mix_path: "mix.exs",
      config_path: "config/config.exs",
      router_path: find_router_path()
    }

    results = ConfigUpdater.update_files(config)

    # Report results
    Enum.each(results, fn {file, result} ->
      case result do
        {:ok, message} -> Mix.shell().info("   ✓ #{message}")
        :not_modified -> Mix.shell().info("   ℹ️  #{file} already up to date")
        :error -> Mix.shell().error("   ❌ Failed to update #{file}")
        nil -> :ok
      end
    end)

    # Step 6: Summary
    Mix.shell().info("\n✅ Setup complete!")
    Mix.shell().info("\n📋 Summary:")
    Mix.shell().info("   • Added #{length(selected_schemas)} schema(s)")
    Mix.shell().info("   • Generated #{length(selected_schemas) * 2} tool(s)")
    Mix.shell().info("   • Oban bridge: #{if include_oban, do: "enabled", else: "disabled"}")
    Mix.shell().info("   • Namespace: #{if namespace == "", do: "none", else: namespace}")
    Mix.shell().info("   • MCP module: #{Path.basename(mcp_path)}")

    Mix.shell().info("\n📝 Next steps:")
    Mix.shell().info("   1. Run: mix deps.get")
    Mix.shell().info("   2. Start server: mix phx.server")
    Mix.shell().info("   3. Test at: http://localhost:4000/mcp")

    Mix.shell().info("\n💡 Tip: You can modify #{mcp_path} to customize the exposed schemas.")

    :ok
  end

  # Private functions

  defp prompt_for_schema_selection(schemas) do
    # Display schemas with numbers
    Enum.with_index(schemas, fn schema, index ->
      Mix.shell().info("   [#{index + 1}] #{schema.module}")
    end)

    Mix.shell().info("")

    # Get selections
    selections = prompt_for_selections(schemas)

    # Return selected schemas
    Enum.map(selections, fn index ->
      schemas |> Enum.at(index - 1)
    end)
  end

  defp prompt_for_selections(schemas) do
    Mix.shell().info("? Select schemas to expose (comma-separated numbers, e.g., 1,2,3)")

    input = get_input()

    # Parse comma-separated numbers with validation
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

    get_input() |> String.trim()
  end

  defp get_input do
    Mix.shell().input("> ")
  end

  defp get_mcp_module_path do
    # Try to detect the app name from mix.exs or use default
    app_name = detect_app_name() || "my_app"
    "lib/#{app_name}/mcp.ex"
  end

  defp detect_app_name do
    # Read mix.exs to find the app name
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

  defp find_router_path do
    # Look for router file in standard Phoenix locations
    possible_paths = [
      "lib/my_app_web/router.ex",
      "lib/my_app/router.ex"
    ]

    # Try to detect actual path
    app_name = detect_app_name()

    paths =
      if app_name do
        [
          "lib/#{app_name}_web/router.ex",
          "lib/#{app_name}/router.ex"
          | possible_paths
        ]
      else
        possible_paths
      end

    Enum.find(paths, &File.exists?/1)
  end
end
