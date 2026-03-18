defmodule Ectomancer.Expose do
  @moduledoc """
  Macro for auto-generating CRUD tools from Ecto schemas.

  This module provides the `expose/2` macro that automatically generates
  MCP tools for Ecto schema CRUD operations.

  ## Example

      defmodule MyApp.MCP do
        use Ectomancer

        expose MyApp.Accounts.User,
          actions: [:list, :get, :create, :update],
          only: [:id, :email, :name, :role]

        expose MyApp.Blog.Post,
          actions: [:list, :get],
          except: [:internal_notes]
      end

  ## Options

    * `:actions` - List of actions to expose: `:list`, `:get`, `:create`, `:update`, `:destroy`
    * `:only` - Whitelist of fields to include
    * `:except` - Blacklist of fields to exclude
    * `:namespace` - Prefix tools with namespace (e.g., `:accounts` → `accounts_list_users`)
    * `:as` - Alternative name for the resource (e.g., `:admin_users` → `list_admin_users`)
    * `:readonly` - Enable read-only mode (disables `:create`, `:update`, `:destroy`)
    * `:authorize` - Authorization configuration (function, policy module, or action-specific rules)

  ## Generated Tools

  For a schema `MyApp.Accounts.User` with actions `[:list, :get, :create]`:

    * `list_users` - List all users with optional filters
    * `get_user` - Get a user by ID
    * `create_user` - Create a new user

  ## Field Filtering

  Fields can be filtered using `:only` or `:except`:

      # Only expose specific fields
      expose User, only: [:email, :name]

      # Exclude sensitive fields
      expose User, except: [:password_hash, :secret_token]

  ## Handling Naming Collisions

  When exposing multiple schemas that might have naming conflicts:

      # Use namespace to prefix all tools
      expose MyApp.Accounts.User, namespace: :accounts
      # Generates: accounts_list_users, accounts_get_user, etc.

      # Use 'as' to rename the resource entirely
      expose MyApp.Accounts.User, as: :admin_users
      # Generates: list_admin_users, get_admin_users, etc.

  ## Action Details

    * `:list` - Returns paginated list, supports filtering
    * `:get` - Returns single record by primary key
    * `:create` - Creates new record with provided attributes
    * `:update` - Updates existing record by primary key
    * `:destroy` - Deletes record by primary key

  ## Authorization

  You can add authorization to exposed schemas using the `:authorize` option:

      # Global authorization for all actions
      expose MyApp.Accounts.User,
        authorize: fn actor, action -> actor.role == :admin end

      # Policy module
      expose MyApp.Accounts.User,
        authorize: with: MyApp.Policies.UserPolicy

      # Action-specific authorization
      expose MyApp.Accounts.User,
        actions: [:list, :get, :create],
        authorize: [
          list: :public,
          get: :public,
          create: fn actor, _action -> actor.role == :admin end
        ]

  ## Repo Configuration

  The CRUD operations require an Ecto Repo. Configure it in your config:

      config :ectomancer, :repo, MyApp.Repo
  """

  alias Ectomancer.SchemaIntrospection

  # Action configurations for data-driven generation
  @action_configs %{
    list: %{prefix: "list", suffix: "s", description_template: "List all %{resource}s"},
    get: %{prefix: "get", suffix: "", description_template: "Get a %{resource} by ID"},
    create: %{prefix: "create", suffix: "", description_template: "Create a new %{resource}"},
    update: %{
      prefix: "update",
      suffix: "",
      description_template: "Update an existing %{resource}"
    },
    destroy: %{prefix: "destroy", suffix: "", description_template: "Delete a %{resource}"}
  }

  @doc """
  Exposes an Ecto schema as MCP tools.

  ## Parameters

    * `schema_module` - The Ecto schema module to expose
    * `opts` - Options for tool generation
      * `:actions` - List of actions (default: `[:list, :get, :create, :update, :destroy]`)
      * `:only` - Whitelist fields
      * `:except` - Blacklist fields
      * `:namespace` - Prefix tools with namespace
      * `:as` - Alternative resource name

   ## Examples

       expose MyApp.Accounts.User
       # Generates: list_users, get_user, create_user, update_user, destroy_user

       expose MyApp.Accounts.User, actions: [:list, :get]
       # Generates: list_users, get_user

       expose MyApp.Accounts.User, readonly: true
       # Generates: list_users, get_user (mutation operations disabled)

       expose MyApp.Accounts.User, only: [:email, :name]
       # All tools only expose email and name fields

       expose MyApp.Accounts.User, namespace: :accounts
       # Generates: accounts_list_users, accounts_get_user, etc.

       expose MyApp.Accounts.User, as: :admin_users
       # Generates: list_admin_users, get_admin_users, etc.
  """
  defmacro expose(schema_module, opts \\ []) do
    schema = Macro.expand(schema_module, __CALLER__)

    # Compile-time validations and data extraction
    validate_schema_compiled!(schema)

    config = build_expose_config(schema, opts)

    # Generate tool definitions for each action
    tool_definitions =
      Enum.map(config.actions, fn action ->
        tool_name = build_tool_name(action, config.resource_name, config.namespace)
        check_collision!(__CALLER__.module, tool_name)
        generate_tool(action, config, tool_name)
      end)

    quote do
      (unquote_splicing(tool_definitions))
    end
  end

  # Configuration building

  defp build_expose_config(schema, opts) do
    introspection = SchemaIntrospection.analyze(schema)
    auth_config = parse_authorization_config(Keyword.get(opts, :authorize))
    readonly = Keyword.get(opts, :readonly, false)

    base_actions = Keyword.get(opts, :actions, [:list, :get, :create, :update, :destroy])
    actions = filter_actions_for_readonly(base_actions, readonly)

    %{
      schema: schema,
      actions: actions,
      exposed_fields: filter_fields(introspection, opts),
      writable_fields: filter_writable_fields(introspection, opts),
      resource_name: determine_resource_name(schema, opts[:as]),
      namespace: opts[:namespace],
      introspection: introspection,
      authorization: auth_config,
      readonly: readonly
    }
  end

  defp filter_actions_for_readonly(actions, true) do
    Enum.filter(actions, fn action -> action in [:list, :get] end)
  end

  defp filter_actions_for_readonly(actions, _), do: actions

  defp parse_authorization_config(nil), do: nil
  defp parse_authorization_config(:none), do: nil

  defp parse_authorization_config(handler) when is_function(handler, 2) do
    %{global: handler, actions: %{}}
  end

  defp parse_authorization_config(module) when is_atom(module) do
    %{global: module, actions: %{}}
  end

  defp parse_authorization_config({:with, _, [module]}) do
    %{global: module, actions: %{}}
  end

  # Handle inline function AST
  defp parse_authorization_config({:fn, _, _} = fn_ast) do
    %{global: fn_ast, actions: %{}}
  end

  # Handle function capture AST
  defp parse_authorization_config({:&, _, _} = capture_ast) do
    %{global: capture_ast, actions: %{}}
  end

  # Handle [with: Module] syntax for policy modules
  defp parse_authorization_config(with: module) when is_atom(module) do
    %{global: module, actions: %{}}
  end

  defp parse_authorization_config(action_rules) when is_list(action_rules) do
    global = Keyword.get(action_rules, :all) || Keyword.get(action_rules, :global)

    # Convert action rules to map, preserving AST nodes
    actions =
      action_rules
      |> Keyword.drop([:all, :global])
      |> Map.new()

    %{global: global, actions: actions}
  end

  defp parse_authorization_config(invalid) do
    raise ArgumentError,
          "Invalid authorization configuration: #{inspect(invalid)}. " <>
            "Expected: function, module, or keyword list of action rules"
  end

  defp filter_fields(introspection, opts) do
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except, [])

    case only do
      nil ->
        Enum.reject(introspection.fields, fn f ->
          f in except or f in [:inserted_at, :updated_at]
        end)

      whitelist ->
        Enum.filter(whitelist, fn f -> f in introspection.fields end)
    end
  end

  defp filter_writable_fields(introspection, opts) do
    filter_fields(introspection, opts)
    |> Enum.reject(fn f -> f in introspection.primary_key end)
  end

  defp determine_resource_name(schema, as_name) do
    base_name =
      schema
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    case as_name do
      nil -> base_name
      name when is_atom(name) -> Atom.to_string(name)
      name when is_binary(name) -> name
    end
  end

  # Validation functions

  defp validate_schema_compiled!(schema) do
    case Code.ensure_compiled(schema) do
      {:module, _} ->
        :ok

      {:error, reason} ->
        raise ArgumentError,
              "Could not compile schema #{inspect(schema)}: #{reason}. " <>
                "Make sure the schema module is defined before using expose."
    end
  end

  defp check_collision!(caller_module, tool_name) do
    tool_module = Module.concat(caller_module, "Tool.#{Macro.camelize(to_string(tool_name))}")

    if Code.ensure_loaded?(tool_module) do
      IO.warn("""
      Tool naming collision detected!

      The tool name `#{tool_name}` appears to be already defined.
      This can happen when:
      - Multiple schemas have the same base name
      - You're exposing the same schema twice

      To avoid collisions, use the :namespace or :as options:

          expose MyApp.Accounts.User, namespace: :accounts
          # or
          expose MyApp.Accounts.User, as: :admin_users

      Generated tool: #{inspect(tool_module)}
      """)
    end
  end

  # Tool generation with proper param support
  # Params are now fully enabled with JSON Schema format for external communication
  # Validation is handled internally in Ectomancer.Repo

  defp generate_tool(action, config, tool_name) do
    description = build_description(action, config.resource_name, config.namespace)
    params = generate_params(action, config)
    auth_block = generate_authorization_block(action, config)

    handler =
      quote do
        fn params, _actor ->
          Ectomancer.Repo.unquote(action)(unquote(config.schema), params)
        end
      end

    quote do
      tool unquote(tool_name) do
        description(unquote(description))
        unquote(params)
        unquote(auth_block)
        handle(unquote(handler))
      end
    end
  end

  defp generate_authorization_block(action, config) do
    auth_config = config.authorization
    do_generate_authorization_block(auth_config, action)
  end

  defp do_generate_authorization_block(nil, _action) do
    quote do
      authorize(:none)
    end
  end

  defp do_generate_authorization_block(%{global: global, actions: actions}, action)
       when map_size(actions) > 0 do
    # Check for action-specific authorization first
    case Map.get(actions, action) do
      nil -> resolve_global_auth(global)
      action_auth -> parse_auth_handler(action_auth)
    end
  end

  defp do_generate_authorization_block(%{global: global}, _action) do
    resolve_global_auth(global)
  end

  defp resolve_global_auth(nil), do: quote(do: authorize(:none))
  defp resolve_global_auth(handler), do: parse_auth_handler(handler)

  defp parse_auth_handler(:none), do: quote(do: authorize(:none))
  defp parse_auth_handler(:public), do: quote(do: authorize(:none))
  defp parse_auth_handler(nil), do: quote(do: authorize(:none))

  defp parse_auth_handler(module) when is_atom(module) do
    quote do
      authorize(with: unquote(module))
    end
  end

  defp parse_auth_handler(handler) when is_function(handler) do
    quote do
      authorize(unquote(handler))
    end
  end

  defp parse_auth_handler({:fn, _, _} = fn_ast) do
    quote do
      authorize(unquote(fn_ast))
    end
  end

  defp parse_auth_handler({:&, _, _} = capture_ast) do
    quote do
      authorize(unquote(capture_ast))
    end
  end

  defp parse_auth_handler(handler) do
    raise ArgumentError,
          "Invalid authorization handler: #{inspect(handler)}"
  end

  # Generate param declarations based on action type
  defp generate_params(:list, _config) do
    # List action typically doesn't require specific params
    # but can accept filter params
    quote do
      # List supports optional filter params
    end
  end

  defp generate_params(:get, config) do
    # Get action requires the primary key
    pk_field = hd(config.introspection.primary_key)
    pk_type = get_ecto_type_for_param(Map.get(config.introspection.types, pk_field))

    quote do
      param(unquote(pk_field), unquote(pk_type), required: true)
    end
  end

  defp generate_params(:create, config) do
    # Create action requires all writable fields
    build_param_block(config.writable_fields, config.introspection.types)
  end

  defp generate_params(:update, config) do
    # Update action requires primary key + writable fields
    pk_field = hd(config.introspection.primary_key)
    pk_type = get_ecto_type_for_param(Map.get(config.introspection.types, pk_field))

    writable_params = build_param_block(config.writable_fields, config.introspection.types)

    quote do
      param(unquote(pk_field), unquote(pk_type), required: true)
      unquote(writable_params)
    end
  end

  defp generate_params(:destroy, config) do
    # Destroy action requires the primary key
    pk_field = hd(config.introspection.primary_key)
    pk_type = get_ecto_type_for_param(Map.get(config.introspection.types, pk_field))

    quote do
      param(unquote(pk_field), unquote(pk_type), required: true)
    end
  end

  defp build_param_block(fields, types) do
    fields
    |> Enum.map(fn field ->
      type = Map.get(types, field)
      param_type = get_ecto_type_for_param(type)

      quote do
        param(unquote(field), unquote(param_type))
      end
    end)
    |> case do
      [] -> quote(do: :ok)
      [single] -> single
      multiple -> {:__block__, [], multiple}
    end
  end

  # Map Ecto types to Peri/MCP types
  defp get_ecto_type_for_param(:string), do: :string
  defp get_ecto_type_for_param(:integer), do: :integer
  defp get_ecto_type_for_param(:float), do: :float
  defp get_ecto_type_for_param(:decimal), do: :float
  defp get_ecto_type_for_param(:boolean), do: :boolean
  defp get_ecto_type_for_param(:date), do: :string
  defp get_ecto_type_for_param(:time), do: :string
  defp get_ecto_type_for_param(:naive_datetime), do: :string
  defp get_ecto_type_for_param(:utc_datetime), do: :string
  defp get_ecto_type_for_param(:binary_id), do: :string
  defp get_ecto_type_for_param(:id), do: :integer
  defp get_ecto_type_for_param(Ecto.UUID), do: :string
  defp get_ecto_type_for_param({:array, _}), do: :list
  defp get_ecto_type_for_param(:map), do: :map
  defp get_ecto_type_for_param(_), do: :string

  # Tool name building - data-driven approach

  defp build_tool_name(action, resource_name, namespace) do
    config = @action_configs[action]
    singular = singularize_resource(resource_name)
    base = "#{config.prefix}_#{singular}#{config.suffix}"

    full_name = if namespace, do: "#{namespace}_#{base}", else: base
    String.to_atom(full_name)
  end

  defp build_description(action, resource_name, namespace) do
    config = @action_configs[action]
    description = String.replace(config.description_template, "%{resource}", resource_name)

    if namespace do
      "[#{namespace}] #{description}"
    else
      description
    end
  end

  defp singularize_resource(name) when is_binary(name) do
    if String.ends_with?(name, "s") do
      String.slice(name, 0..-2//1)
    else
      name
    end
  end
end
