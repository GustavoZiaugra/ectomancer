defmodule Mix.Tasks.Ectomancer.Teardown do
  @moduledoc """
  Removes Ectomancer configuration from your Phoenix/Ecto project.

  This Mix task provides an interactive workflow to undo what `mix ectomancer.setup`
  does. It removes the generated MCP module, dependency, configuration entries,
  and router route.

  ## Usage

      mix ectomancer.teardown

  ## Workflow

  1. Detects app name from mix.exs
  2. Prompts for confirmation before making changes
  3. Removes the generated MCP module (if it exists)
  4. Removes Ectomancer dependency from mix.exs
  5. Removes Ectomancer config from config/config.exs
  6. Removes Ectomancer Plug route from router
  7. Prints summary of what was removed

  ## Return Codes

  - `0` - Success (everything cleaned up)
  - `1` - Nothing to clean up
  - `2` - Operation cancelled by user
  - `3` - File operation error
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile")

    unless Mix.env() == :test do
      Mix.shell().info("\n🧹 Tearing down Ectomancer...")
    end

    app_name = detect_app_name()

    unless anything_to_cleanup?(app_name) do
      unless Mix.env() == :test do
        Mix.shell().info("\n✅ Nothing to clean up — Ectomancer is not installed.")
      end

      exit({:shutdown, 1})
    end

    unless confirm_teardown!() do
      Mix.shell().info("\n   Teardown cancelled.")
      exit({:shutdown, 2})
    end

    results = %{
      mcp_module: remove_mcp_module(app_name),
      mix_exs: remove_mix_dependency(),
      config_exs: remove_ectomancer_config(),
      router_exs: remove_router_route(app_name)
    }

    print_results(results)
    :ok
  end

  @doc false
  def anything_to_cleanup?(app_name) do
    mcp_path = mcp_module_path(app_name)

    File.exists?(mcp_path) ||
      has_dependency?() ||
      has_config?() ||
      (router_path(app_name) && has_route?(router_path(app_name)))
  end

  defp confirm_teardown! do
    Mix.shell().info(
      "\n⚠️  This will remove Ectomancer files and configuration from your project."
    )

    Mix.shell().info("\n? Proceed with teardown? (y/N)")

    case IO.gets("> ") do
      :eof -> false
      {:error, _} -> false
      input when input in ["y\n", "Y\n", "yes\n", "Yes\n"] -> true
      _ -> false
    end
  end

  # MCP Module

  @doc false
  def mcp_module_path(app_name) do
    "lib/#{app_name || "my_app"}/mcp.ex"
  end

  defp remove_mcp_module(app_name) do
    path = mcp_module_path(app_name)

    if File.exists?(path) do
      File.rm!(path)

      # Remove empty parent directory if it only contained mcp.ex
      parent = Path.dirname(path)

      if File.exists?(parent) and dir_empty?(parent) do
        File.rmdir!(parent)
      end

      {:ok, "Removed #{path}"}
    else
      :not_found
    end
  end

  # Mix Dependency

  @doc false
  def has_dependency? do
    case File.read("mix.exs") do
      {:ok, content} -> String.contains?(content, "{:ectomancer,")
      _ -> false
    end
  end

  defp remove_mix_dependency do
    case File.read("mix.exs") do
      {:ok, content} ->
        if String.contains?(content, "{:ectomancer,") do
          remove_mix_dependency_content(content)
        else
          :not_found
        end

      _ ->
        :error
    end
  end

  @doc false
  def remove_mix_dependency_content(content) do
    updated =
      content
      |> String.replace(~r/\s*\{:ectomancer,\s*"[^"]*"\s*},?\s*\n/, "\n")
      |> String.replace(~r/\s*\{:ectomancer,\s*"[^"]*"\s*},?/, "")

    if updated != content do
      File.write!("mix.exs", updated)
      {:ok, "Removed Ectomancer dependency from mix.exs"}
    else
      :error
    end
  end

  # Config

  @doc false
  def has_config? do
    case File.read("config/config.exs") do
      {:ok, content} -> String.contains?(content, "config :ectomancer,")
      _ -> false
    end
  end

  defp remove_ectomancer_config do
    path = "config/config.exs"

    case File.read(path) do
      {:ok, content} ->
        if String.contains?(content, "config :ectomancer,") do
          remove_ectomancer_config_content(path, content)
        else
          :not_found
        end

      _ ->
        :error
    end
  end

  @doc false
  def remove_ectomancer_config_content(path, content) do
    updated =
      content
      |> String.replace(
        ~r/\n\s*# Ectomancer MCP Server Configuration\n\s*config :ectomancer,\n\s*repo: [^\n]+\n*/,
        "\n"
      )
      |> String.trim()
      |> Kernel.<>("\n")

    if updated != content do
      File.write!(path, updated)
      {:ok, "Removed Ectomancer config from config/config.exs"}
    else
      :error
    end
  end

  # Router

  @doc false
  def router_path(app_name) do
    if app_name do
      ["lib/#{app_name}_web/router.ex", "lib/#{app_name}/router.ex"]
      |> Enum.find(&File.exists?/1)
    end
  end

  @doc false
  def has_route?(path) do
    case File.read(path) do
      {:ok, content} -> String.contains?(content, "Ectomancer.Plug")
      _ -> false
    end
  end

  defp remove_router_route(app_name) do
    case router_path(app_name) do
      nil ->
        :not_found

      path ->
        remove_router_route_path(path)
    end
  end

  defp remove_router_route_path(path) do
    case File.read(path) do
      {:ok, content} ->
        if String.contains?(content, "Ectomancer.Plug") do
          remove_router_route_content(path, content)
        else
          :not_found
        end

      _ ->
        :error
    end
  end

  @doc false
  def remove_router_route_content(path, content) do
    updated =
      content
      |> String.replace(
        ~r/\n\s*# Ectomancer MCP\n\s*forward\s+"\/mcp",\s*Ectomancer\.Plug\n*/,
        "\n"
      )
      |> String.trim_trailing()
      |> Kernel.<>("\n")

    if updated != content do
      File.write!(path, updated)
      {:ok, "Removed Ectomancer route from #{Path.basename(path)}"}
    else
      :error
    end
  end

  # Helpers

  @doc false
  def detect_app_name do
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

  @doc false
  def dir_empty?(dir) do
    case File.ls!(dir) do
      [] -> true
      _ -> false
    end
  end

  @doc false
  def print_results(results) do
    removed = Enum.count(results, fn {_, v} -> match?({:ok, _}, v) end)
    errors = Enum.count(results, fn {_, v} -> v == :error end)

    Mix.shell().info("\n📋 Teardown summary:")

    Enum.each(results, fn {key, result} ->
      label = key |> Atom.to_string() |> String.replace("_", " ") |> String.upcase()

      case result do
        {:ok, message} -> Mix.shell().info("   ✓ #{message}")
        :not_found -> Mix.shell().info("   ℹ️  #{label}: not found (already removed?)")
        :error -> Mix.shell().error("   ❌ #{label}: failed to remove")
      end
    end)

    Mix.shell().info("\n✅ Teardown complete! Removed #{removed} item(s).")

    if errors > 0 do
      Mix.shell().error(
        "   #{errors} error(s) occurred. You may need to manually clean up some files."
      )
    end
  end
end
