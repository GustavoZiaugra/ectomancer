defmodule Ectomancer.Installer.TemplateRenderer do
  @moduledoc """
  Renders EEx templates for Ectomancer setup files.

  Generates:
  - MCP module with exposed schemas
  - Config entry snippets
  - Router route snippets
  """

  @doc """
  Generates MCP module with exposed schemas.

  ## Arguments

    * `opts` - Keyword list with options:
      * `:schemas` - List of schema info maps
      * `:mcp_name` - MCP server name (default: "my-app-mcp")
      * `:mcp_version` - MCP server version (default: "1.0.0")
      * `:namespace` - Tool namespace (default: nil)
      * `:include_oban` - Whether to include Oban bridge
      * `:output_path` - Where to save the file
      * `:module_name` - Module name for the generated MCP module (default: "MyApp.MCP")

  ## Returns

    Tuple with status and generated content:
    {:ok, content} | :not_modified | :error
  """
  @spec generate_mcp_module(keyword()) :: {:ok, String.t()} | :not_modified | :error
  def generate_mcp_module(opts \\ []) do
    schemas = Keyword.get(opts, :schemas, [])
    mcp_name = Keyword.get(opts, :mcp_name, "my-app-mcp")
    mcp_version = Keyword.get(opts, :mcp_version, "1.0.0")
    namespace = Keyword.get(opts, :namespace, nil)
    include_oban = Keyword.get(opts, :include_oban, false)
    output_path = Keyword.get(opts, :output_path, "lib/my_app/mcp.ex")
    module_name = Keyword.get(opts, :module_name, "MyApp.MCP")

    existing_content =
      if File.exists?(output_path) do
        File.read!(output_path)
      else
        ""
      end

    generated_content =
      generate_mcp_module_content(schemas, mcp_name, mcp_version, namespace, include_oban,
        module_name: module_name
      )

    if generated_content == existing_content do
      :not_modified
    else
      File.mkdir_p!(Path.dirname(output_path))
      File.write!(output_path, generated_content)
      {:ok, "Generated MCP module at #{output_path}"}
    end
  end

  @doc """
  Generates config entry for Ectomancer.
  """
  @spec generate_config_entry(keyword()) :: String.t()
  def generate_config_entry(opts \\ []) do
    repo = Keyword.get(opts, :repo, "MyApp.Repo")

    """

    # Ectomancer MCP Server Configuration
    config :ectomancer,
      repo: #{repo}

    """
  end

  @doc """
  Generates router route for Ectomancer.
  """
  @spec generate_router_entry(keyword()) :: String.t()
  def generate_router_entry(_opts \\ []) do
    """

    # Ectomancer MCP
    forward "/mcp", Ectomancer.Plug

    """
  end

  @doc """
  Generates complete MCP module content with default namespace and no oban.
  """
  @spec generate_mcp_module_content(list(map()), String.t(), String.t()) :: String.t()
  def generate_mcp_module_content(schemas, mcp_name, mcp_version) do
    generate_mcp_module_content(schemas, mcp_name, mcp_version, nil, false)
  end

  @doc """
  Generates complete MCP module content.
  """
  @spec generate_mcp_module_content(
          list(map()),
          String.t(),
          String.t(),
          String.t() | nil,
          boolean(),
          keyword()
        ) :: String.t()
  def generate_mcp_module_content(
        schemas,
        mcp_name,
        mcp_version,
        namespace,
        include_oban,
        opts \\ []
      ) do
    module_name = Keyword.get(opts, :module_name, "MyApp.MCP")
    expose_lines = Enum.map_join(schemas, "\n\n", &generate_expose_line(&1, namespace))

    oban_line =
      if include_oban do
        "\n\n  expose_oban_jobs"
      else
        ""
      end

    """
    defmodule #{module_name} do
      use Ectomancer,
        name: "#{mcp_name}",
        version: "#{mcp_version}"

    #{expose_lines}#{oban_line}
    end
    """
  end

  defp generate_expose_line(schema, namespace) do
    actions = determine_actions(schema)

    namespace_opt =
      if namespace && namespace != "",
        do: ",\n    namespace: :#{Macro.underscore(namespace)}",
        else: ""

    "  expose #{inspect(schema.module)},\n    actions: #{actions}#{namespace_opt}"
  end

  defp determine_actions(schema) do
    if Enum.any?(schema.writable_fields) do
      "[:list, :get, :create, :update, :destroy]"
    else
      "[:list, :get]"
    end
  end
end
