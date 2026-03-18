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

  ## Authorization

  Tools can have authorization to control access:

      # Inline function
      tool :admin_only do
        description("Admin only action")
        authorize(fn actor, _action -> actor.role == :admin end)

        handle(fn _params, _actor ->
          {:ok, "Secret data"}
        end)
      end

      # Policy module
      tool :with_policy do
        description("Uses policy module")
        authorize(with: MyApp.Policies.MyPolicy)

        handle(fn _params, _actor ->
          {:ok, "Protected data"}
        end)
      end

      # No authorization (public)
      tool :public do
        description("Public endpoint")
        authorize(:none)

        handle(fn _params, _actor ->
          {:ok, "Public data"}
        end)
      end
  """
  defmacro tool(name, do: block) do
    tool_name_str = to_string(name)
    {description, params, auth_handler, handler_ast} = parse_tool_block(block)

    # Build Peri schema for Anubis validation (atom keys)
    peri_schema = build_peri_schema(params)
    # Build JSON Schema for external clients (string keys)
    json_schema = build_json_schema(params)

    # Infer action name from tool name for authorization
    action = tool_action_from_name(tool_name_str)

    quote do
      tool_module_name =
        Module.concat(__MODULE__, "Tool.#{Macro.camelize(unquote(tool_name_str))}")

      Ectomancer.Tool.define_tool_module(
        tool_module_name,
        unquote(tool_name_str),
        unquote(action),
        unquote(description),
        unquote(Macro.escape(peri_schema)),
        unquote(Macro.escape(json_schema)),
        unquote(auth_handler),
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
             action,
             description,
             peri_schema,
             json_schema_for_clients,
             auth_handler,
             handler_ast
           ) do
    quote do
      defmodule unquote(module_name) do
        @moduledoc unquote(description)
        @tool_name unquote(tool_name)
        @action unquote(action)

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

          # Check authorization before executing
          case check_authorization(actor, @action) do
            :ok ->
              handler = unquote(handler_ast)
              do_execute(handler, params, actor, frame)

            {:error, reason} ->
              error = %Anubis.MCP.Error{
                code: -32_001,
                message: "Unauthorized: #{reason}",
                data: %{}
              }

              {:error, error, frame}
          end
        end

        defp check_authorization(actor, action) do
          auth_handler = unquote(auth_handler)

          if auth_handler do
            Ectomancer.Authorization.check(actor, action, handler: auth_handler)
          else
            :ok
          end
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

    Enum.reduce(
      items,
      {"", [], nil, quote(do: fn _, _ -> {:ok, nil} end)},
      fn item, {desc, params, auth_handler, handler} ->
        case item do
          {:description, _, [text]} ->
            {text, params, auth_handler, handler}

          {:param, _, [name, type | rest]} ->
            opts = extract_opts(rest)
            {desc, [{name, type, opts} | params], auth_handler, handler}

          {:authorize, _, [handler]} ->
            auth_handler = parse_authorize_handler(handler)
            {desc, params, auth_handler, handler}

          {:handle, _, [handler_block]} ->
            {desc, params, auth_handler, handler_block}

          _ ->
            {desc, params, auth_handler, handler}
        end
      end
    )
  end

  defp parse_authorize_handler(handler) do
    case handler do
      :none ->
        nil

      [with: module] ->
        module

      {:with, _, [module]} ->
        module

      {:fn, _, _} = fn_ast ->
        fn_ast

      {:&, _, _} = capture_ast ->
        capture_ast

      handler when is_function(handler) ->
        handler

      _ ->
        raise ArgumentError,
              "Invalid authorization handler. Use: authorize(fn actor, action -> ...), authorize(with: Module), or authorize(:none)"
    end
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
  Defines authorization for a tool.

  ## Examples

      # Inline function
      authorize fn actor, action ->
        actor.role == :admin or action in [:list, :get]
      end

      # Policy module
      authorize with: MyApp.Policies.UserPolicy

      # No authorization (public)
      authorize :none
  """
  defmacro authorize(handler) do
    quote do
      authorize(unquote(handler))
    end
  end

  # Infer action type from tool name for authorization
  defp tool_action_from_name(tool_name) do
    tool_name
    |> String.downcase()
    |> case do
      name when name in ["list", "index", "all"] -> :list
      name when name in ["get", "find", "show"] -> :get
      name when name in ["create", "new", "add"] -> :create
      name when name in ["update", "edit", "modify"] -> :update
      name when name in ["destroy", "delete", "remove"] -> :destroy
      _ -> :execute
    end
  end

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
    errors = map_changeset_errors(changeset)
    validation_type = infer_validation_type(errors)

    field_errors =
      errors
      |> Enum.map(fn {field, messages} ->
        %{
          field: format_field_name(field),
          message: Enum.join(messages, ", ")
        }
      end)

    data = %{errors: field_errors, count: length(field_errors)}

    message =
      case validation_type do
        :presence -> "Missing required field(s)"
        :format -> "Invalid format for field(s)"
        :inclusion -> "Invalid value for field(s)"
        :confirmation -> "Confirmation does not match"
        :length -> "Invalid length for field(s)"
        :comparison -> "Invalid value for field(s)"
        _ -> "Validation failed"
      end

    {-32_602, message, data}
  end

  def format_error(reason) when is_binary(reason) do
    cond do
      field_match = extract_null_violation_field(reason) ->
        format_null_violation_error(field_match, reason)

      not_found_error?(reason) ->
        {-32_002, "Resource not found", %{details: reason}}

      foreign_key_error?(reason) ->
        {-32_602, "Invalid reference: Related record does not exist", %{details: reason}}

      unique_constraint_error?(reason) ->
        {-32_602, "Duplicate value: Record with this value already exists", %{details: reason}}

      not_null_error?(reason) ->
        {-32_602, "Missing required value", %{details: reason}}

      true ->
        {-32_603, "Tool execution failed", %{reason: reason}}
    end
  end

  def format_error(reason) do
    {-32_603, "Tool execution failed", %{reason: inspect(reason)}}
  end

  # Helper functions for format_error/1

  defp extract_null_violation_field(reason) when is_binary(reason) do
    ~r/null value in column "([^"]+)"/i
    |> Regex.run(reason)
  end

  defp format_null_violation_error(field_match, reason) when is_list(field_match) do
    field_name = Enum.at(field_match, 1)
    formatted_field = format_field_name(field_name)

    {-32_602, "Missing required parameter: #{formatted_field}",
     %{field: field_name, details: reason}}
  end

  defp not_found_error?(reason) when is_binary(reason) do
    String.contains?(reason, "not found")
  end

  defp foreign_key_error?(reason) when is_binary(reason) do
    String.contains?(reason, "violates foreign key") ||
      String.contains?(reason, "foreign_key_violation")
  end

  defp unique_constraint_error?(reason) when is_binary(reason) do
    String.contains?(reason, "duplicate key") ||
      String.contains?(reason, "unique_violation") ||
      String.contains?(reason, "23505")
  end

  defp not_null_error?(reason) when is_binary(reason) do
    String.contains?(reason, "not_null_violation") ||
      String.contains?(reason, "23502")
  end

  @doc """
  Maps Ecto changeset errors to a structured format suitable for MCP responses.

  Returns a map where keys are field names (atoms) and values are lists of error strings.

  ## Examples

      changeset = %Ecto.Changeset{
        errors: [email: {"can't be blank", []}],
        ...
      }

      Ectomancer.Tool.map_changeset_errors(changeset)
      # %{email: ["can't be blank"]}
  """
  @spec map_changeset_errors(Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  def map_changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  @doc """
  Flattens mapped changeset errors into a single map with concatenated messages.

  ## Examples

      errors = %{email: ["can't be blank"], name: ["is invalid"]}
      Ectomancer.Tool.flatten_errors(errors)
      # %{email: "can't be blank", name: "is invalid"}
  """
  @spec flatten_errors(%{atom() => [String.t()]}) :: %{atom() => String.t()}
  def flatten_errors(errors) when is_map(errors) do
    errors
    |> Enum.map(fn {field, messages} ->
      {field, Enum.join(messages, ", ")}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Formats a field name for display in error messages.
  Converts snake_case to Title Case.
  """
  @spec format_field_name(atom() | String.t()) :: String.t()
  def format_field_name(field) do
    field
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  @doc """
  Infers the validation type from changeset errors.

  Accepts either a map with list values (from traverse_errors) or a map with string values.
  """
  @spec infer_validation_type(%{atom() => String.t()} | %{atom() => [String.t()]}) :: atom()
  def infer_validation_type(errors) when is_map(errors) do
    # Normalize errors to a single string for pattern matching
    error_messages =
      errors
      |> Map.values()
      |> List.flatten()
      |> Enum.join(" ")

    cond do
      String.contains?(error_messages, "can't be blank") -> :presence
      String.contains?(error_messages, "has invalid format") -> :format
      String.contains?(error_messages, "is invalid") -> :inclusion
      String.contains?(error_messages, "doesn't match confirmation") -> :confirmation
      String.contains?(error_messages, "string too") -> :length
      String.contains?(error_messages, "must be") -> :comparison
      true -> :other
    end
  end
end
