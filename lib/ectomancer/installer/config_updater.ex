defmodule Ectomancer.Installer.ConfigUpdater do
  @moduledoc """
  Updates project configuration files for Ectomancer integration.

  Handles:
  - Adding dependency to mix.exs
  - Adding repo config to config/config.exs
  - Adding Plug route to router file
  """

  @doc """
  Updates all necessary configuration files for Ectomancer.

  ## Arguments

    * `opts` - Keyword list with options:
      * `:mix_path` - Path to mix.exs (default: "mix.exs")
      * `:config_path` - Path to config/config.exs (default: "config/config.exs")
      * `:router_path` - Path to router file (auto-detected)

  ## Returns

    Map with status of each update:
    %{
      mix_exs: {:ok, "added dependency"} | :not_modified | :error,
      config_exs: {:ok, "added config"} | :not_modified | :error,
      router_exs: {:ok, "added route"} | :not_modified | :error
    }
  """
  @spec update_files(keyword()) :: map()
  def update_files(opts \\ []) do
    mix_path = Keyword.get(opts, :mix_path, "mix.exs")
    config_path = Keyword.get(opts, :config_path, "config/config.exs")
    router_path = Keyword.get(opts, :router_path, nil)

    %{
      mix_exs: update_mix_exs(mix_path),
      config_exs: update_config_exs(config_path),
      router_exs: router_path && update_router_exs(router_path)
    }
  end

  @doc """
  Updates mix.exs to add Ectomancer dependency.
  """
  @spec update_mix_exs(String.t()) :: {:ok, String.t()} | :not_modified | :error
  def update_mix_exs(path) do
    unless File.exists?(path) do
      :error
    else
      content = File.read!(path)

      # Check if already added
      if String.contains?(content, "{:ectomancer,") do
        :not_modified
      else
        # Find deps section and add dependency
        updated_content = content |> add_to_deps_section()

        if updated_content != content do
          File.write!(path, updated_content)
          {:ok, "Added {:ectomancer, \\\"~> 1.0\\\"} to mix.exs"}
        else
          :not_modified
        end
      end
    end
  end

  @doc """
  Updates config/config.exs with Ectomancer repo configuration.
  """
  @spec update_config_exs(String.t()) :: {:ok, String.t()} | :not_modified | :error
  def update_config_exs(path) do
    unless File.exists?(path) do
      :error
    else
      content = File.read!(path)

      # Check if already configured
      if String.contains?(content, "config :ectomancer,") do
        :not_modified
      else
        # Add config entry
        updated_content = content |> add_ectomancer_config()

        if updated_content != content do
          File.write!(path, updated_content)
          {:ok, "Added Ectomancer config to config/config.exs"}
        else
          :not_modified
        end
      end
    end
  end

  @doc """
  Updates router file with Ectomancer Plug route.
  """
  @spec update_router_exs(String.t()) :: {:ok, String.t()} | :not_modified | :error
  def update_router_exs(path) do
    unless File.exists?(path) do
      :error
    else
      content = File.read!(path)

      # Check if already added
      if String.contains?(content, "Ectomancer.Plug") do
        :not_modified
      else
        # Add forward route
        updated_content = content |> add_ectomancer_route()

        if updated_content != content do
          File.write!(path, updated_content)
          {:ok, "Added MCP route to router"}
        else
          :not_modified
        end
      end
    end
  end

  # Private functions

  defp add_to_deps_section(content) do
    # Look for deps: [...] section
    ~r/defp deps\(\) do\s+\[(.*?)\]/s
    |> Regex.run(content)
    |> case do
      [_, deps_content] ->
        # Add ectomancer dependency
        new_deps =
          deps_content
          |> String.replace_trailing("]", ")")
          |> String.replace("]", ")")
          |> String.replace(",)", ",\n      {:ectomancer, \\\"~> 1.0\\\"},\n      )")

        "defp deps() do\n      [\n#{new_deps}"

      _ ->
        # If deps section not found, append to end of file
        content
        |> String.trim_trailing()
        |> String.concat("\n\n      # Ectomancer\n      {:ectomancer, \\\"~> 1.0\\\"}\n    ]")
    end
  end

  defp add_ectomancer_config(content) do
    # Look for config sections and add ectomancer config
    # Insert after existing configs or at end
    content
    |> String.replace_trailing("\n", "\n")
    |> String.replace(
      ~r/(config :.*?,\s*\{)/,
      "#{elem(Regexp.last_capture(), 1)}\n    # Ectomancer MCP Server\n    config :ectomancer,\n      repo: MyApp.Repo\n    ,"
    )
    |> String.replace(
      ~r/(\}\s*$)/,
      "#{elem(Regexp.last_capture(), 1)}\n    # Ectomancer MCP Server\n    config :ectomancer,\n      repo: MyApp.Repo\n    ,"
    )
  end

  defp add_ectomancer_route(content) do
    # Look for forward patterns in router
    # Add before pipeline or at end

    # Try to find existing forward calls
    if Regex.run(~r/forward\s*\([^)]+\)/, content) do
      # Replace existing forward or add after
      content
      |> String.replace(
        ~r/(forward\s+\["\/[^\"]+",\s+[^,]+,\s+[^"]+"\s*\))/,
        "#{elem(Regexp.last_capture(), 1)}\n    forward \"/mcp\", Ectomancer.Plug"
      )
      |> String.replace(
        ~r/(pipeline\s+\([^)]+\)\s+do)/,
        "#{elem(Regexp.last_capture(), 1)}\n    forward \"/mcp\", Ectomancer.Plug"
      )
    else
      # No forward found, add to end
      content
      |> String.replace_trailing("\n", "\n")
      |> String.concat("\n    # Ectomancer MCP\n    forward \"/mcp\", Ectomancer.Plug")
    end
  end
end
