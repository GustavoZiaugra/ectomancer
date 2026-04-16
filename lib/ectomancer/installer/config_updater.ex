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
      router_exs: if(router_path, do: update_router_exs(router_path))
    }
  end

  @doc """
  Updates mix.exs to add Ectomancer dependency.
  """
  @spec update_mix_exs(String.t()) :: {:ok, String.t()} | :not_modified | :error
  def update_mix_exs(path) do
    if File.exists?(path) do
      do_update_mix_exs(File.read!(path), path)
    else
      :error
    end
  end

  defp do_update_mix_exs(content, path) do
    if String.contains?(content, "{:ectomancer,") do
      :not_modified
    else
      updated_content = add_to_deps_section(content)

      if updated_content != content do
        File.write!(path, updated_content)
        {:ok, "Added {:ectomancer, \"~> 1.0\"} to mix.exs"}
      else
        :not_modified
      end
    end
  end

  @doc """
  Updates config/config.exs with Ectomancer repo configuration.
  """
  @spec update_config_exs(String.t()) :: {:ok, String.t()} | :not_modified | :error
  def update_config_exs(path) do
    if File.exists?(path) do
      do_update_config_exs(File.read!(path), path)
    else
      :error
    end
  end

  defp do_update_config_exs(content, path) do
    if String.contains?(content, "config :ectomancer,") do
      :not_modified
    else
      updated_content = add_ectomancer_config(content)

      if updated_content != content do
        File.write!(path, updated_content)
        {:ok, "Added Ectomancer config to config/config.exs"}
      else
        :not_modified
      end
    end
  end

  @doc """
  Updates router file with Ectomancer Plug route.
  """
  @spec update_router_exs(String.t()) :: {:ok, String.t()} | :not_modified | :error
  def update_router_exs(path) do
    if File.exists?(path) do
      do_update_router_exs(File.read!(path), path)
    else
      :error
    end
  end

  defp do_update_router_exs(content, path) do
    if String.contains?(content, "Ectomancer.Plug") do
      :not_modified
    else
      updated_content = add_ectomancer_route(content)

      if updated_content != content do
        File.write!(path, updated_content)
        {:ok, "Added MCP route to router"}
      else
        :not_modified
      end
    end
  end

  defp add_to_deps_section(content) do
    case Regex.run(~r/defp deps[(]?[)]? do\s+\[(.*?)\]/s, content) do
      [full_match, deps_content] ->
        new_deps = deps_content <> "\n      {:ectomancer, \"~> 1.0\"},"
        String.replace(content, full_match, "defp deps() do\n      [" <> new_deps)

      _ ->
        content
    end
  end

  defp add_ectomancer_config(content) do
    ectomancer_config = """

    # Ectomancer MCP Server Configuration
    config :ectomancer,
      repo: MyApp.Repo
    """

    content
    |> String.trim_trailing()
    |> Kernel.<>(ectomancer_config)
  end

  defp add_ectomancer_route(content) do
    route_line = "\n    # Ectomancer MCP\n    forward \"/mcp\", Ectomancer.Plug"

    cond do
      Regex.match?(~r/forward\s+"/, content) ->
        Regex.replace(
          ~r/(forward\s+"[^"]+",\s+[^\n]+)(\n)(?!\s*forward)/,
          content,
          "\\1\\2#{route_line}\\2"
        )

      Regex.match?(~r/pipeline\s+:/, content) ->
        Regex.replace(
          ~r/(\n)(\s*pipeline\s+:)/,
          content,
          "\\1#{route_line}\\1\\2"
        )

      true ->
        Regex.replace(
          ~r/(\nend\s*)$/,
          content,
          "#{route_line}\\1"
        )
    end
  end
end
