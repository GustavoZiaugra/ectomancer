defmodule Ectomancer.Igniter do
  @moduledoc """
  Igniter installer for Ectomancer.

  This module provides the installer callback used by `mix igniter.install ectomancer`.
  It reuses the existing `Ectomancer.Installer.*` modules for discovery, generation,
  and configuration updates, while using Igniter utilities for supervision tree patching.

  > Igniter handles adding `{:ectomancer, "~> 1.5"}` to `mix.exs` automatically —
  > this installer focuses on the remaining setup steps.

  ## Usage

      mix igniter.install ectomancer

  The installer will:
  1. Check for required dependencies (Ecto, Plug)
  2. Discover Ecto schemas in your project
  3. Prompt you to select which schemas to expose
  4. Generate an MCP module exposing the selected schemas
  5. Configure Ectomancer in `config/config.exs`
  6. Add the MCP route to your Phoenix router
  7. Add the Anubis supervisor to your application supervision tree
  """

  alias Ectomancer.Installer.ConfigUpdater
  alias Ectomancer.Installer.DependencyChecker
  alias Ectomancer.Installer.SchemaDiscovery
  alias Ectomancer.Installer.TemplateRenderer

  @doc """
  Igniter installer callback.

  Called by `mix igniter.install ectomancer` after the dependency is added.
  Returns a modified `%Igniter{}` struct with accumulated changes.
  """
  @spec install(Igniter.t(), keyword()) :: Igniter.t()
  def install(igniter, _opts) do
    unless Mix.env() == :test do
      Mix.shell().info("\n🚀 Installing Ectomancer...")
    end

    check_dependencies!()
    schemas = discover_schemas!()
    selected_schemas = select_schemas!(schemas)
    optional_deps = DependencyChecker.check_optional()
    include_oban = if :oban in optional_deps, do: prompt_for_oban_bridge(), else: false
    namespace = prompt_for_namespace()
    app_name = detect_app_name()

    generate_mcp_module(selected_schemas, include_oban, namespace, app_name)
    update_configuration_files(app_name)

    igniter
    |> add_supervisor_child(app_name)
  end

  defp check_dependencies! do
    case DependencyChecker.check_required() do
      :ok ->
        unless Mix.env() == :test do
          Mix.shell().info("   ✓ Required dependencies found")
        end

      {:error, missing} ->
        unless Mix.env() == :test do
          Mix.shell().error("\n❌ Missing required dependencies!")
          Mix.shell().error(DependencyChecker.missing_deps_message(missing))
        end

        Mix.raise("Cannot install Ectomancer: missing required dependencies")
    end
  end

  defp discover_schemas! do
    unless Mix.env() == :test do
      Mix.shell().info("\n🔍 Scanning for Ecto schemas...")
    end

    unless Mix.env() == :test do
      Mix.Task.run("compile")
    end

    schemas = SchemaDiscovery.discover()

    if Enum.empty?(schemas) do
      unless Mix.env() == :test do
        Mix.shell().error("\n❌ No Ecto schemas found!")
      end

      Mix.raise("Cannot install Ectomancer: no Ecto schemas found in your project")
    end

    unless Mix.env() == :test do
      Mix.shell().info("\n📦 Found #{length(schemas)} schema(s):")

      Enum.each(schemas, fn schema ->
        Mix.shell().info("   ✓ #{inspect(schema.module)}")
      end)
    end

    schemas
  end

  defp select_schemas!(schemas) do
    if Mix.env() == :test do
      schemas
    else
      selected = Mix.Tasks.Ectomancer.Setup.prompt_for_schema_selection(schemas)

      if selected == [] do
        Mix.shell().error("\n❌ No schemas selected!")
        Mix.raise("Cannot install Ectomancer: no schemas selected")
      end

      selected
    end
  end

  defp prompt_for_oban_bridge do
    Mix.shell().info("? Include Oban bridge? (y/N)")

    case IO.gets("> ") |> String.downcase() |> String.trim() do
      input when input in ["y", "yes"] -> true
      _ -> false
    end
  end

  defp prompt_for_namespace do
    Mix.shell().info("? Tool namespace? (e.g., 'MyApp', leave empty for none)")

    case IO.gets("> ") |> String.trim() do
      "" -> nil
      value -> value
    end
  end

  defp generate_mcp_module(selected_schemas, include_oban, namespace, app_name) do
    unless Mix.env() == :test do
      Mix.shell().info("\n📝 Generating MCP module...")
    end

    mcp_path = get_mcp_module_path(app_name)
    module_name = mcp_module_name(app_name)

    result =
      TemplateRenderer.generate_mcp_module(
        schemas: selected_schemas,
        output_path: mcp_path,
        include_oban: include_oban,
        namespace: namespace,
        module_name: module_name
      )

    unless Mix.env() == :test do
      case result do
        {:ok, message} ->
          Mix.shell().info("   ✓ #{message}")

        :not_modified ->
          Mix.shell().info("   ℹ️  MCP module already exists and is up to date")
      end
    end

    mcp_path
  end

  defp update_configuration_files(app_name) do
    unless Mix.env() == :test do
      Mix.shell().info("\n⚙️  Updating configuration files...")
    end

    results = %{
      config_exs: ConfigUpdater.update_config_exs("config/config.exs"),
      router_exs:
        case find_router_path(app_name) do
          nil -> nil
          path -> ConfigUpdater.update_router_exs(path)
        end
    }

    unless Mix.env() == :test do
      print_config_update_results(results)
    end
  end

  defp add_supervisor_child(igniter, app_name) do
    unless Mix.env() == :test do
      Mix.shell().info("\n🔧 Adding supervisor child...")
    end

    module_name = mcp_module_name(app_name)
    app_mod = Igniter.Project.Application

    if Code.ensure_loaded?(app_mod) && function_exported?(app_mod, :add_new_child, 2) do
      igniter
      |> app_mod.add_new_child(
        {Anubis.Server.Supervisor,
         {Module.concat([module_name]), transport: {:streamable_http, start: true}}}
      )
    else
      unless Mix.env() == :test do
        Mix.shell().info(
          "   ⚠️  Could not add supervisor child (Igniter not available). Add it manually:"
        )

        Mix.shell().info(
          "      {Anubis.Server.Supervisor, {#{module_name}, transport: {:streamable_http, start: true}}}"
        )
      end

      igniter
    end
  end

  @doc false
  def print_config_update_results(results) do
    Enum.each(results, fn {file, result} ->
      case result do
        {:ok, message} -> Mix.shell().info("   ✓ #{message}")
        :not_modified -> Mix.shell().info("   ℹ️  #{file} already up to date")
        :error -> Mix.shell().error("   ❌ Failed to update #{file}")
        nil -> :ok
      end
    end)
  end

  @doc false
  def detect_app_name do
    Mix.Tasks.Ectomancer.Setup.detect_app_name()
  end

  @doc false
  def get_mcp_module_path(app_name) do
    Mix.Tasks.Ectomancer.Setup.get_mcp_module_path(app_name)
  end

  @doc false
  def mcp_module_name(app_name) do
    Mix.Tasks.Ectomancer.Setup.mcp_module_name(app_name)
  end

  @doc false
  def find_router_path(app_name) do
    Mix.Tasks.Ectomancer.Setup.find_router_path(app_name)
  end
end
