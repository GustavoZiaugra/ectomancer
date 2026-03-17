defmodule Ectomancer.Tool do
  @moduledoc """
  Custom tool DSL for defining MCP tools.

  Tools are defined with:
  - description: What the tool does
  - params: Input parameters (with types and requirements)
  - handle: The function that executes the tool logic

  The DSL generates a tool module that integrates with Anubis MCP.
  Validation is handled internally rather than by Anubis's Peri validator
  to avoid JSON encoding issues with Peri's tuple-based schema format.
  """

  @doc """
  Defines a new tool within an Ectomancer module.

  ## Example

      tool :greet do
        description("Greet someone by name")
        param(:name, :string, required: true)

        handle(fn params, _actor ->
          name = params["name"]
          {:ok, "Hello, \#{name}!"}
        end)
      end
  """
  defmacro tool(name, do: block) do
    tool_name_str = to_string(name)
    {description, params, handler_ast} = parse_tool_block(block)

    # Build Peri schema for Anubis validation (atom keys)
    peri_schema = build_peri_schema(params)
    # Build JSON Schema for external clients (string keys)
    json_schema = build_json_schema(params)

    quote do
      tool_module_name =
        Module.concat(__MODULE__, "Tool.#{Macro.camelize(unquote(tool_name_str))}")

      Ectomancer.Tool.define_tool_module(
        tool_module_name,
        unquote(tool_name_str),
        unquote(description),
        unquote(Macro.escape(peri_schema)),
        unquote(Macro.escape(json_schema)),
        unquote(handler_ast)
      )

      require Anubis.Server
      Anubis.Server.component(tool_module_name, name: unquote(tool_name_str))
    end
  end

  @doc false
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defmacro define_tool_module(
             module_name,
             tool_name,
             description,
             peri_schema,
             json_schema_for_clients,
             handler_ast
           ) do
    quote do
      defmodule unquote(module_name) do
        @moduledoc unquote(description)
        @tool_name unquote(tool_name)

        # Suppress compiler warnings about dead code when handler only returns {:ok, ...}
        @compile {:no_warn_unused, execute: 2}

        def name, do: @tool_name
        def description, do: @moduledoc
        def __mcp_component_type__, do: :tool
        def __description__, do: @moduledoc

        # Peri schema for Anubis validation (atom keys)
        def __mcp_raw_schema__, do: unquote(peri_schema)
        # JSON Schema for external clients (string keys, JSON encodable)
        def input_schema, do: unquote(json_schema_for_clients)

        def execute(params, frame) do
          actor = frame.assigns[:ectomancer_actor]
          handler = unquote(handler_ast)
          do_execute(handler, params, actor, frame)
        end

        # Helper function to hide handler return type from compiler analysis
        # This prevents "clause will never match" warnings when test handlers
        # only return {:ok, _} - the compiler can't track types through this function
        @dialyzer {:nowarn_function, do_execute: 4}
        defp do_execute(handler, params, actor, frame) when is_function(handler, 2) do
          result = handler.(params, actor)

          case result do
            {:ok, data} ->
              response = %Anubis.Server.Response{
                type: :tool,
                content: [%{"type" => "text", "text" => inspect(data)}]
              }

              {:reply, response, frame}

            {:error, reason} ->
              {code, message, data} = Ectomancer.Tool.format_error(reason)
              error = %Anubis.MCP.Error{code: code, message: message, data: data}
              {:error, error, frame}
          end
        rescue
          e ->
            error = %Anubis.MCP.Error{
              code: -32_603,
              message: "Tool execution error: #{Exception.message(e)}",
              data: %{
                error: inspect(e),
                stacktrace: Exception.format_stacktrace(__STACKTRACE__)
              }
            }

            {:error, error, frame}
        end
      end
    end
  end

  # Parse tool block to extract components
  defp parse_tool_block(block) do
    # Handle the block which is a __block__ containing the tool definitions
    # Flatten nested __block__ structures
    items =
      case block do
        {:__block__, _, inner_items} -> flatten_block_items(inner_items)
        single -> [single]
      end

    Enum.reduce(items, {"", [], quote(do: fn _, _ -> {:ok, nil} end)}, fn item,
                                                                          {desc, params, handler} ->
      case item do
        {:description, _, [text]} ->
          {text, params, handler}

        {:param, _, [name, type | rest]} ->
          opts = extract_opts(rest)
          {desc, [{name, type, opts} | params], handler}

        {:handle, _, [handler_block]} ->
          {desc, params, handler_block}

        _ ->
          {desc, params, handler}
      end
    end)
  end

  # Flatten nested __block__ items
  defp flatten_block_items(items) do
    Enum.flat_map(items, fn
      {:__block__, _, inner} -> flatten_block_items(inner)
      other -> [other]
    end)
  end

  # Build Peri schema for Anubis validation (atom keys)
  defp build_peri_schema(params) do
    Enum.map(params, fn {name, type, opts} ->
      full_type =
        if opts[:required], do: {:required, type_to_peri(type)}, else: type_to_peri(type)

      {name, full_type}
    end)
    |> Enum.into(%{})
  end

  # Build JSON Schema for external clients (string keys, JSON encodable)
  defp build_json_schema(params) do
    properties =
      Enum.map(params, fn {name, type, _} ->
        {to_string(name), %{"type" => type_to_json(type)}}
      end)
      |> Enum.into(%{})

    required =
      Enum.filter(params, fn {_, _, opts} -> opts[:required] end)
      |> Enum.map(fn {name, _, _} -> to_string(name) end)

    schema = %{"type" => "object", "properties" => properties}
    if required != [], do: Map.put(schema, "required", required), else: schema
  end

  # Map DSL types to Peri types
  defp type_to_peri(:string), do: :string
  defp type_to_peri(:integer), do: :integer
  defp type_to_peri(:float), do: :float
  defp type_to_peri(:boolean), do: :boolean
  defp type_to_peri(:list), do: {:list, :string}
  defp type_to_peri(:map), do: :map
  defp type_to_peri(_), do: :string

  # Map DSL types to JSON Schema types
  defp type_to_json(:string), do: "string"
  defp type_to_json(:integer), do: "integer"
  defp type_to_json(:float), do: "number"
  defp type_to_json(:boolean), do: "boolean"
  defp type_to_json(:list), do: "array"
  defp type_to_json(:map), do: "object"
  defp type_to_json(_), do: "string"

  defp extract_opts([]), do: []
  defp extract_opts([opts | _]), do: opts

  @doc """
  Formats error reasons into proper MCP error format with descriptive messages.
  This function is called from generated tool modules.
  """
  @spec format_error(any()) :: {integer(), String.t(), map()}
  def format_error(:missing_primary_key) do
    {-32_602, "Invalid params: Missing required primary key", %{field: :id}}
  end

  def format_error(:no_primary_key) do
    {-32_602, "Invalid params: Schema has no primary key defined", %{}}
  end

  def format_error(:repo_not_configured) do
    {-32_603, "Internal error: Repository not configured",
     %{
       help: "Configure :ectomancer, :repo in your config files"
     }}
  end

  def format_error(:not_found) do
    {-32_002, "Resource not found", %{}}
  end

  def format_error(%Ecto.Changeset{} = changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)

    {-32_602, "Validation failed", %{errors: errors}}
  end

  def format_error(reason) when is_binary(reason) do
    # Try to extract field name from database error messages
    # PostgreSQL errors often contain "null value in column ... violates not-null constraint"
    field_pattern = ~r/null value in column "([^"]+)"/
    field_match = Regex.run(field_pattern, reason)

    # Check if it's a database error
    cond do
      field_match ->
        # Extract field name from error message
        field_name = Enum.at(field_match, 1)
        formatted_field = field_name |> String.replace("_", " ") |> String.capitalize()

        {-32_602, "Missing required parameter: #{formatted_field}",
         %{field: field_name, details: reason}}

      String.contains?(reason, "not found") ->
        {-32_002, "Resource not found", %{details: reason}}

      String.contains?(reason, "violates foreign key") ->
        {-32_602, "Invalid reference: Related record does not exist", %{details: reason}}

      String.contains?(reason, "duplicate key") ->
        {-32_602, "Duplicate value: Record with this value already exists", %{details: reason}}

      true ->
        {-32_603, "Tool execution failed", %{reason: reason}}
    end
  end

  def format_error(reason) do
    {-32_603, "Tool execution failed", %{reason: inspect(reason)}}
  end
end
