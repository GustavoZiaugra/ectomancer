defmodule Ectomancer.Tool do
  @moduledoc """
  Custom tool DSL for defining MCP tools.

  ## Example

      defmodule MyApp.MCP do
        use Ectomancer

        tool :send_password_reset do
          description "Send a password reset email to a user"
          param :email, :string, required: true

          handle fn %{email: email}, actor ->
            MyApp.Accounts.send_reset_email(email, actor)
          end
        end
      end

  ## Parameter Types

  - `:string` - String value
  - `:integer` - Integer value
  - `:float` - Float/number value
  - `:boolean` - Boolean value
  - `:map` - Object value
  - `{:array, type}` - Array of values

  ## Options

  - `:required` - Whether the parameter is required (default: false)
  - `:description` - Parameter description
  - `:enum` - List of allowed values
  - `:default` - Default value for optional parameters
  """

  @doc """
  Defines a new tool within an Ectomancer module.

  ## Example

      tool :send_password_reset do
        description "Send a password reset email to a user"
        param :email, :string, required: true

        handle fn %{email: email}, actor ->
          MyApp.Accounts.send_reset_email(email, actor)
        end
      end
  """
  defmacro tool(name, do: block) do
    tool_name_str = to_string(name)

    quote do
      # Initialize accumulators in process dictionary
      _ = Process.put(:ectomancer_schema_fields, [])
      _ = Process.put(:ectomancer_required_fields, [])
      _ = Process.put(:ectomancer_tool_description, "")
      _ = Process.put(:ectomancer_tool_handler, nil)

      # Execute the DSL block
      import Ectomancer.Tool.DSL
      unquote(block)

      # Collect accumulated values
      schema_fields = Process.get(:ectomancer_schema_fields, [])
      required_fields = Process.get(:ectomancer_required_fields, [])
      description = Process.get(:ectomancer_tool_description, "")
      handler = Process.get(:ectomancer_tool_handler)

      # Clean up process dictionary
      Process.delete(:ectomancer_schema_fields)
      Process.delete(:ectomancer_required_fields)
      Process.delete(:ectomancer_tool_description)
      Process.delete(:ectomancer_tool_handler)

      # Create tool module name
      tool_module_name =
        Module.concat(__MODULE__, "Tool.#{Macro.camelize(unquote(tool_name_str))}")

      # Register handler if present - do this OUTSIDE the defmodule to avoid compile warning
      if handler do
        Ectomancer.Tool.__register_handler__(tool_module_name, handler)
      end

      # Generate the tool module
      defmodule tool_module_name do
        @moduledoc description

        @tool_name unquote(tool_name_str)
        @tool_description description
        @schema_fields schema_fields
        @required_fields required_fields

        def name, do: @tool_name

        def description, do: @tool_description

        def input_schema do
          properties =
            Map.new(@schema_fields, fn {name, type, _opts} ->
              {to_string(name), Ectomancer.Tool.type_to_json_schema(type)}
            end)

          schema = %{
            "type" => "object",
            "properties" => properties
          }

          if @required_fields != [] do
            Map.put(schema, "required", Enum.map(@required_fields, &to_string/1))
          else
            schema
          end
        end

        # Mark this as a tool component for Anubis
        def __mcp_component_type__, do: :tool

        def __description__, do: @moduledoc

        def execute(params, frame) do
          actor = frame.assigns[:ectomancer_actor]
          Ectomancer.Tool.__execute__(__MODULE__, params, actor)
        end
      end

      # Register the component using Anubis's component macro
      require Anubis.Server
      Anubis.Server.component(tool_module_name, name: unquote(tool_name_str))
    end
  end

  @doc false
  def __register_handler__(tool_module, handler) do
    handlers = Application.get_env(:ectomancer, :ectomancer_tool_handlers, %{})

    Application.put_env(
      :ectomancer,
      :ectomancer_tool_handlers,
      Map.put(handlers, tool_module, handler)
    )
  end

  @doc false
  def __execute__(tool_module, params, actor) do
    handlers = Application.get_env(:ectomancer, :ectomancer_tool_handlers, %{})

    case Map.get(handlers, tool_module) do
      nil -> {:ok, nil}
      handler -> handler.(params, actor)
    end
  end

  @doc false
  def type_to_json_schema(type) do
    case type do
      :string -> %{"type" => "string"}
      :integer -> %{"type" => "integer"}
      :float -> %{"type" => "number"}
      :boolean -> %{"type" => "boolean"}
      :map -> %{"type" => "object"}
      {:array, inner_type} -> %{"type" => "array", "items" => type_to_json_schema(inner_type)}
      _ -> %{"type" => "string"}
    end
  end
end

defmodule Ectomancer.Tool.DSL do
  @moduledoc """
  DSL macros for defining tools.
  """

  @doc """
  Sets the tool description.

  ## Example

      description "Send a password reset email to a user"
  """
  defmacro description(text) do
    quote do
      Process.put(:ectomancer_tool_description, unquote(text))
    end
  end

  @doc """
  Defines a parameter for the tool.

  ## Parameters

    * `name` - The parameter name (atom)
    * `type` - The parameter type (:string, :integer, :float, :boolean, :map, or {:array, type})
    * `opts` - Options for the parameter

  ## Options

    * `:required` - Whether the parameter is required (default: false)
    * `:description` - Parameter description
    * `:enum` - List of allowed values
    * `:default` - Default value

  ## Examples

      param :email, :string, required: true
      param :count, :integer, required: false, default: 10
      param :tags, {:array, :string}
  """
  defmacro param(name, type, opts \\ []) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      current_fields = Process.get(:ectomancer_schema_fields) || []
      Process.put(:ectomancer_schema_fields, [{name, type, opts} | current_fields])

      if opts[:required] do
        current_required = Process.get(:ectomancer_required_fields) || []
        Process.put(:ectomancer_required_fields, [name | current_required])
      end
    end
  end

  @doc """
  Defines the handler function for the tool.

  The handler receives `params` (map of parameters) and `actor` (current user or nil).

  ## Example

      handle fn %{email: email}, actor ->
        MyApp.Accounts.send_reset_email(email, actor)
      end

  ## Return Values

  The handler should return:
    * `{:ok, result}` - Successful execution
    * `{:error, reason}` - Failed execution
    * `result` - Any value (will be wrapped in `{:ok, result}`)
  """
  defmacro handle(fun) do
    quote bind_quoted: [fun: fun] do
      Process.put(:ectomancer_tool_handler, fun)
    end
  end
end
