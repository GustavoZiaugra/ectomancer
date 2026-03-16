defmodule Ectomancer.Tool do
  @moduledoc """
  Custom tool DSL for defining MCP tools.
  Stores handlers in a way that's cluster-safe by embedding them at compile time.
  """

  @doc """
  Defines a new tool within an Ectomancer module.
  """
  defmacro tool(name, do: block) do
    tool_name_str = to_string(name)
    {description, params, handler_ast} = parse_tool_block(block)

    schema = Macro.escape(build_schema(params))

    quote do
      tool_module_name =
        Module.concat(__MODULE__, "Tool.#{Macro.camelize(unquote(tool_name_str))}")

      Ectomancer.Tool.define_tool_module(
        tool_module_name,
        unquote(tool_name_str),
        unquote(description),
        unquote(schema),
        unquote(handler_ast)
      )

      require Anubis.Server
      Anubis.Server.component(tool_module_name, name: unquote(tool_name_str))
    end
  end

  @doc false
  # credo:disable-for-lines:40 Credo.Check.Refactor.CyclomaticComplexity
  defmacro define_tool_module(module_name, tool_name, description, schema, handler_ast) do
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
        def __mcp_raw_schema__, do: unquote(schema)
        def input_schema, do: __mcp_raw_schema__()

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
          case handler.(params, actor) do
            {:ok, data} ->
              response = %Anubis.Server.Response{
                type: :tool,
                content: [%{"type" => "text", "text" => inspect(data)}]
              }

              {:reply, response, frame}

            {:error, reason} ->
              error = %Anubis.MCP.Error{
                code: -32_603,
                message: "Tool execution failed",
                data: %{reason: reason}
              }

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
    items =
      case block do
        {:__block__, _, items} -> items
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

  defp build_schema(params) do
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

  defp type_to_json(:string), do: "string"
  defp type_to_json(:integer), do: "integer"
  defp type_to_json(:float), do: "number"
  defp type_to_json(:boolean), do: "boolean"
  defp type_to_json(_), do: "string"

  defp extract_opts([]), do: []
  defp extract_opts([opts | _]), do: opts
end

defmodule Ectomancer.Tool.DSL do
  @moduledoc """
  DSL macros for tool definition.
  These are parsed at compile time and do not execute at runtime.
  """

  # Parsed at macro level
  defmacro description(_text), do: quote(do: nil)
  # Parsed at macro level
  defmacro param(_name, _type, _opts \\ []), do: quote(do: nil)
  # Parsed at macro level - block contains the actual handler
  defmacro handle(do: _block), do: quote(do: nil)
end
