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
  alias Mix.Tasks.Ectomancer.Setup, as: SetupTask

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
      selected = SetupTask.prompt_for_schema_selection(schemas)

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
    module_atom = Module.concat([module_name])
    app_mod = Igniter.Project.Application

    transport = prompt_for_transport()

    if transport == :websocket do
      unless Mix.env() == :test do
        print_websocket_setup_instructions(module_name)
      end

      igniter
    else
      if Code.ensure_loaded?(app_mod) && function_exported?(app_mod, :add_new_child, 2) do
        specs =
          Ectomancer.child_spec(module_atom, transports: [transport])
          |> Enum.map(fn {mod, args} -> {mod, args} end)

        Enum.reduce(specs, igniter, fn spec, acc ->
          app_mod.add_new_child(acc, spec)
        end)
      else
        unless Mix.env() == :test do
          print_manual_supervisor_instruction(module_name, transport)
        end

        igniter
      end
    end
  end

  defp print_websocket_setup_instructions(module_name) do
    Mix.shell().info("\n📋 WebSocket requires additional manual setup:")
    Mix.shell().info("")
    Mix.shell().info("  1. Add to your endpoint (lib/my_app_web/endpoint.ex):")
    Mix.shell().info("")
    Mix.shell().info("       socket \"/mcp/ws\", Ectomancer.Plug.WebSocket,")
    Mix.shell().info("         server: #{module_name},")
    Mix.shell().info("         websocket: [connect_info: [:x_headers, :uri, :peer_data]]")
    Mix.shell().info("")
    Mix.shell().info("  2. Add to config/config.exs:")
    Mix.shell().info("")
    Mix.shell().info("       config :ectomancer, :ws_server, #{module_name}")
    Mix.shell().info("")
    Mix.shell().info("  3. Already running Streamable HTTP or SSE supervisor is reused.")
    Mix.shell().info("     No additional Anubis.Server.Supervisor needed.")
    Mix.shell().info("")
  end

  defp print_manual_supervisor_instruction(module_name, transport) do
    Mix.shell().info(
      "   ⚠️  Could not add supervisor child (Igniter not available). Add it manually:"
    )

    transport_line =
      "{Anubis.Server.Supervisor, {#{module_name}, transport: {#{inspect(transport)}, start: true}}}"

    Mix.shell().info("      #{transport_line}")
  end

  defp prompt_for_transport do
    if Mix.env() == :test do
      :streamable_http
    else
      Mix.shell().info("? Transport type?")
      Mix.shell().info("  1. Streamable HTTP (recommended)")
      Mix.shell().info("  2. SSE (legacy, deprecated)")
      Mix.shell().info("  3. WebSocket (requires manual endpoint config)")

      case IO.gets("> ") |> String.trim() do
        "2" -> :sse
        "3" -> :websocket
        _ -> :streamable_http
      end
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
    SetupTask.detect_app_name()
  end

  @doc false
  def get_mcp_module_path(app_name) do
    SetupTask.get_mcp_module_path(app_name)
  end

  @doc false
  def mcp_module_name(app_name) do
    SetupTask.mcp_module_name(app_name)
  end

  @doc false
  def find_router_path(app_name) do
    SetupTask.find_router_path(app_name)
  end
end
