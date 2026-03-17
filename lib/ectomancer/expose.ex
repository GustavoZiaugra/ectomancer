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

    %{
      schema: schema,
      actions: Keyword.get(opts, :actions, [:list, :get, :create, :update, :destroy]),
      exposed_fields: filter_fields(introspection, opts),
      writable_fields: filter_writable_fields(introspection, opts),
      resource_name: determine_resource_name(schema, opts[:as]),
      namespace: opts[:namespace],
      introspection: introspection
    }
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
        handle(unquote(handler))
      end
    end
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
