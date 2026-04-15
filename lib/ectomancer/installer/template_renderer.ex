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

    existing_content =
      if File.exists?(output_path) do
        File.read!(output_path)
      else
        ""
      end

    generated_content =
      generate_mcp_module_content(schemas, mcp_name, mcp_version, namespace, include_oban)

    if generated_content == existing_content do
      :not_modified
    else
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
  @spec generate_mcp_module_content(list(map()), String.t(), String.t(), atom() | nil, boolean()) ::
          String.t()
  def generate_mcp_module_content(schemas, mcp_name, mcp_version, namespace, include_oban) do
    expose_annotations =
      schemas
      |> Enum.map(&generate_expose_annotation/1)
      |> Enum.join("\n")

    example_tools =
      case Enum.at(schemas, 0) do
        nil -> ""
        schema -> generate_example_tools(schema, namespace)
      end

    oban_section =
      if include_oban do
        """

        # Oban job management tools
        expose_oban_jobs
        """
      else
        ""
      end

    """
    defmodule MyApp.MCP do
      use Ectomancer,
        name: "#{mcp_name}",
        version: "#{mcp_version}"

      # Expose Ecto schemas as MCP tools
      #{expose_annotations}

      #{example_tools}

      #{oban_section}
    end
    """
  end

  defp generate_expose_annotation(schema) do
    module = schema.module
    actions = determine_actions(schema)

    """
      #{generate_tool_definition(module)}
      expose #{inspect(module)},
        actions: #{actions}
    """
  end

  defp determine_actions(schema) do
    writable = Enum.count(schema.writable_fields)

    if writable > 0 do
      "[list, get, create, update, delete]"
    else
      "[list, get]"
    end
  end

  defp generate_tool_definition(module) do
    table_name =
      module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    tool_name = :"#{table_name}_#{String.to_atom("list")}"

    """
      # Auto-generated tool for #{inspect(module)}
      #{tool_name} = :#{table_name}_list
    """
  end

  defp generate_example_tools(schema, namespace) do
    module = schema.module
    table_name = schema.table || "records"

    """

      # Example custom tool for #{inspect(module)}
      #{(namespace && "  ") || ""}tool :#{format_tool_name(module)} do
        #{(namespace && "  ") || ""}description "List #{table_name}"
        #{(namespace && "  ") || ""}authorize :public
        #{(namespace && "  ") || ""}handle fn _params, _actor ->
        #{(namespace && "    ") || "  "}{:ok, []}
        #{(namespace && "  ") || "end"}
      end
    """
  end

  defp format_tool_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end
end
