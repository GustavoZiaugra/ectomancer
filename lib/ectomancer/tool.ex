if Code.ensure_loaded?(Ecto) do
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

      {description, params, auth_handler, parent_auth_handler, handler_ast} =
        parse_tool_block(block)

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
          unquote(handler_ast),
          unquote(parent_auth_handler)
        )

        require Anubis.Server
        Anubis.Server.component(tool_module_name, name: unquote(tool_name_str))
      end
    end

    @doc false
    # credo:disable-for-next-line
    defmacro define_tool_module(
               module_name,
               tool_name,
               action,
               description,
               peri_schema,
               json_schema_for_clients,
               auth_handler,
               handler_ast,
               parent_auth_handler \\ nil
             ) do
      has_auth = not is_nil(auth_handler) or not is_nil(parent_auth_handler)
      execute_clause = build_execute_clause(has_auth, handler_ast)
      auth_clause = build_check_authorization_clause(has_auth, auth_handler, parent_auth_handler)

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

          unquote(execute_clause)
          unquote(auth_clause)

          defp check_rate_limit(actor, frame) do
            case Application.get_env(:ectomancer, :rate_limit) do
              nil ->
                :ok

              config when is_list(config) ->
                max = Keyword.get(config, :max, 100)
                window_ms = Keyword.get(config, :window_ms, 60_000)
                per_actor = Keyword.get(config, :per_actor, false)

                key = if per_actor, do: {:actor, actor}, else: :global

                case Ectomancer.RateLimiter.check(max: max, window_ms: window_ms, key: key) do
                  :ok ->
                    :ok

                  {:error, :rate_limited, retry_after} ->
                    error = %Anubis.MCP.Error{
                      code: -32_029,
                      message: "Rate limited. Try again in #{retry_after}ms",
                      data: %{retry_after_ms: retry_after}
                    }

                    {:error, error, frame}
                end
            end
          end

          # Helper function to hide handler return type from compiler analysis
          # This prevents "clause will never match" warnings when test handlers
          # only return {:ok, _} - the compiler can't track types through this function
          @dialyzer {:nowarn_function, do_execute: 5}
          defp do_execute(handler, params, scope, actor, frame) do
            Ectomancer.Telemetry.tool_span(@tool_name, fn ->
              result =
                cond do
                  is_function(handler, 3) ->
                    handler.(params, actor, scope)

                  is_function(handler, 2) ->
                    handler.(params, actor)

                  true ->
                    raise ArgumentError,
                          "Handler must be a function of arity 2 or 3, got: #{inspect(handler)}"
                end

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
            end)
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

    # Helpers to generate conditional clauses for tool modules.
    # Extracted to keep define_tool_module shallow for Credo.

    defp build_execute_clause(true, handler_ast) do
      quote do
        def execute(params, frame) do
          actor = frame.assigns[:ectomancer_actor]

          case check_authorization(actor, @action) do
            {:ok, :scoped, scope_fn} ->
              with :ok <- check_rate_limit(actor, frame) do
                handler = unquote(handler_ast)
                do_execute(handler, params, scope_fn, actor, frame)
              end

            :ok ->
              with :ok <- check_rate_limit(actor, frame) do
                handler = unquote(handler_ast)
                do_execute(handler, params, nil, actor, frame)
              end

            {:error, reason} ->
              error = %Anubis.MCP.Error{
                code: -32_001,
                message: "Unauthorized: #{reason}",
                data: %{}
              }

              {:error, error, frame}
          end
        end
      end
    end

    defp build_execute_clause(false, handler_ast) do
      quote do
        def execute(params, frame) do
          actor = frame.assigns[:ectomancer_actor]

          with :ok <- check_rate_limit(actor, frame) do
            handler = unquote(handler_ast)
            do_execute(handler, params, nil, actor, frame)
          end
        end
      end
    end

    defp build_check_authorization_clause(true, auth_handler, parent_auth_handler) do
      if is_nil(parent_auth_handler) do
        quote do
          defp check_authorization(actor, action) do
            Ectomancer.Authorization.check(
              actor,
              action,
              handler: unquote(auth_handler)
            )
          end
        end
      else
        quote do
          defp check_authorization(actor, action) do
            Ectomancer.Authorization.check(
              actor,
              action,
              handler: unquote(auth_handler),
              parent_auth: [handler: unquote(parent_auth_handler)]
            )
          end
        end
      end
    end

    defp build_check_authorization_clause(false, _auth_handler, _parent_auth_handler) do
      quote do
        defp check_authorization(_actor, _action), do: :ok
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
        {"", [], nil, nil, quote(do: fn _, _ -> {:ok, nil} end)},
        fn item, {desc, params, auth_handler, parent_auth, handler} ->
          case item do
            {:description, _, [text]} ->
              {text, params, auth_handler, parent_auth, handler}

            {:param, _, [name, type | rest]} ->
              opts = extract_opts(rest)
              {desc, [{name, type, opts} | params], auth_handler, parent_auth, handler}

            {:authorize, _, [handler, [parent_auth: parent]]} ->
              auth_handler = parse_authorize_handler(handler)
              parent_auth = parse_authorize_handler(parent)
              {desc, params, auth_handler, parent_auth, handler}

            {:authorize, _, [handler]} ->
              auth_handler = parse_authorize_handler(handler)
              {desc, params, auth_handler, parent_auth, handler}

            {:handle, _, [handler_block]} ->
              {desc, params, auth_handler, parent_auth, handler_block}

            _ ->
              {desc, params, auth_handler, parent_auth, handler}
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
          {to_string(name), json_property_for_type(type)}
        end)
        |> Enum.into(%{})

      required =
        Enum.filter(params, fn {_, _, opts} -> opts[:required] end)
        |> Enum.map(fn {name, _, _} -> to_string(name) end)

      schema = %{"type" => "object", "properties" => properties}
      if required != [], do: Map.put(schema, "required", required), else: schema
    end

    defp json_property_for_type(type) when is_atom(type), do: %{"type" => type_to_json(type)}

    defp json_property_for_type({:array, inner}) do
      %{"type" => "array", "items" => json_property_for_type(inner)}
    end

    # Map DSL types to Peri types
    defp type_to_peri(:string), do: :string
    defp type_to_peri(:integer), do: :integer
    defp type_to_peri(:float), do: :float
    defp type_to_peri(:boolean), do: :boolean
    defp type_to_peri(:list), do: {:list, :string}
    defp type_to_peri(:map), do: :map
    defp type_to_peri({:array, inner}), do: {:list, type_to_peri(inner)}
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
      name = String.downcase(tool_name)

      prefixes = %{
        "list" => :list,
        "index" => :list,
        "all" => :list,
        "get" => :get,
        "find" => :get,
        "show" => :get,
        "create" => :create,
        "new" => :create,
        "add" => :create,
        "update" => :update,
        "edit" => :update,
        "modify" => :update,
        "destroy" => :destroy,
        "delete" => :destroy,
        "remove" => :destroy
      }

      cond do
        Map.has_key?(prefixes, name) -> Map.get(prefixes, name)
        String.starts_with?(name, "batch_create") -> :batch_create
        String.starts_with?(name, "batch_update") -> :batch_update
        String.starts_with?(name, "batch_destroy") -> :batch_destroy
        true -> :execute
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

    def format_error(:not_soft_deletable) do
      {-32_602, "Invalid params: Schema does not support soft-delete", %{}}
    end

    def format_error({:batch_size_exceeded, limit}) do
      {-32_602, "Batch size exceeds maximum of #{limit}", %{max_batch_size: limit}}
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
else
  defmodule Ectomancer.Tool do
    @moduledoc false

    defmacro tool(_name, do: _block) do
      quote do
      end
    end

    # credo:disable-for-next-line
    defmacro define_tool_module(
               _module_name,
               _tool_name,
               _action,
               _description,
               _peri_schema,
               _json_schema,
               _auth_handler,
               _handler_ast,
               _parent_auth_handler \\ nil
             ) do
      quote do
      end
    end

    defmacro authorize(_handler) do
      quote do
      end
    end

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

    def format_error({:batch_size_exceeded, limit}) do
      {-32_602, "Batch size exceeds maximum of #{limit}", %{max_batch_size: limit}}
    end

    def format_error(reason) when is_binary(reason) do
      {-32_603, "Tool execution failed", %{reason: reason}}
    end

    def format_error(reason) do
      {-32_603, "Tool execution failed", %{reason: inspect(reason)}}
    end

    def map_changeset_errors(_changeset), do: %{}
    def flatten_errors(errors) when is_map(errors), do: errors
    def format_field_name(field), do: to_string(field)
    def infer_validation_type(_errors), do: :other
  end
end
