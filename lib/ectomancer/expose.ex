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

  alias Ectomancer.SchemaBuilder
  alias Ectomancer.SchemaIntrospection

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
    actions = Keyword.get(opts, :actions, [:list, :get, :create, :update, :destroy])
    only_fields = Keyword.get(opts, :only)
    except_fields = Keyword.get(opts, :except, [])
    namespace = Keyword.get(opts, :namespace)
    as_name = Keyword.get(opts, :as)

    # Get schema information at compile time
    # schema_module is quoted, so we need to evaluate it
    schema = Macro.expand(schema_module, __CALLER__)
    introspection = SchemaIntrospection.analyze(schema)

    # Determine which fields to expose
    exposed_fields =
      case only_fields do
        nil ->
          # Exclude blacklisted fields and internal fields
          introspection.fields
          |> Enum.reject(fn field ->
            field in except_fields or field in [:inserted_at, :updated_at]
          end)

        whitelist ->
          # Use only whitelisted fields (and ensure they exist)
          whitelist
          |> Enum.filter(fn field -> field in introspection.fields end)
      end

    # Get writable fields (exclude primary key)
    writable_fields =
      exposed_fields
      |> Enum.reject(fn field -> field in introspection.primary_key end)

    # Get resource name from module
    base_resource_name =
      schema
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    # Apply 'as' option if provided
    resource_name =
      case as_name do
        nil -> base_resource_name
        name when is_atom(name) -> Atom.to_string(name)
        name when is_binary(name) -> name
      end

    # Generate tool definitions for each action
    tool_definitions =
      Enum.map(actions, fn action ->
        tool_name = build_tool_name(action, resource_name, namespace)

        # Check for potential collisions by examining already defined modules
        check_collision(__CALLER__.module, tool_name)

        generate_tool_definition(
          action,
          resource_name,
          schema,
          exposed_fields,
          writable_fields,
          introspection,
          namespace
        )
      end)

    # Return all tool definitions
    quote do
      (unquote_splicing(tool_definitions))
    end
  end

  # Check if a tool with this name might collide with existing tools
  defp check_collision(caller_module, tool_name) do
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

  # Generate a single tool definition
  defp generate_tool_definition(
         action,
         resource_name,
         schema,
         exposed_fields,
         writable_fields,
         introspection,
         namespace
       ) do
    tool_name = build_tool_name(action, resource_name, namespace)

    input_schema =
      build_action_schema(action, schema, exposed_fields, writable_fields, introspection)

    description = build_description(action, resource_name, namespace)
    params = build_params(input_schema)

    quote do
      tool unquote(tool_name) do
        description(unquote(description))

        unquote_splicing(params)

        handle(fn params, _actor ->
          Ectomancer.Repo.unquote(action)(unquote(schema), params)
        end)
      end
    end
  end

  # Build tool name based on action and optional namespace
  defp build_tool_name(:list, resource_name, nil) do
    singular = singularize_resource(resource_name)
    String.to_atom("list_#{singular}s")
  end

  defp build_tool_name(:list, resource_name, namespace) do
    singular = singularize_resource(resource_name)
    String.to_atom("#{namespace}_list_#{singular}s")
  end

  defp build_tool_name(:get, resource_name, nil),
    do: String.to_atom("get_#{resource_name}")

  defp build_tool_name(:get, resource_name, namespace),
    do: String.to_atom("#{namespace}_get_#{resource_name}")

  defp build_tool_name(:create, resource_name, nil),
    do: String.to_atom("create_#{resource_name}")

  defp build_tool_name(:create, resource_name, namespace),
    do: String.to_atom("#{namespace}_create_#{resource_name}")

  defp build_tool_name(:update, resource_name, nil),
    do: String.to_atom("update_#{resource_name}")

  defp build_tool_name(:update, resource_name, namespace),
    do: String.to_atom("#{namespace}_update_#{resource_name}")

  defp build_tool_name(:destroy, resource_name, nil),
    do: String.to_atom("destroy_#{resource_name}")

  defp build_tool_name(:destroy, resource_name, namespace),
    do: String.to_atom("#{namespace}_destroy_#{resource_name}")

  defp build_tool_name(action, resource_name, nil),
    do: String.to_atom("#{action}_#{resource_name}")

  defp build_tool_name(action, resource_name, namespace),
    do: String.to_atom("#{namespace}_#{action}_#{resource_name}")

  # Helper to ensure resource name is singular for pluralization
  # Simple heuristic: if it ends with 's', remove it
  defp singularize_resource(name) when is_binary(name) do
    if String.ends_with?(name, "s") do
      String.slice(name, 0..-2//1)
    else
      name
    end
  end

  # Build input schema for specific action
  defp build_action_schema(:create, schema, _exposed, writable_fields, _introspection) do
    SchemaBuilder.build(schema, writable_fields)
  end

  defp build_action_schema(:update, schema, _exposed, writable_fields, introspection) do
    pk = introspection.primary_key
    all_fields = pk ++ writable_fields
    SchemaBuilder.build(schema, all_fields, required: [])
  end

  defp build_action_schema(:get, schema, _exposed, _writable, introspection) do
    SchemaBuilder.build(schema, introspection.primary_key)
  end

  defp build_action_schema(:destroy, schema, _exposed, _writable, introspection) do
    SchemaBuilder.build(schema, introspection.primary_key)
  end

  defp build_action_schema(:list, schema, exposed_fields, _writable, _introspection) do
    SchemaBuilder.build(schema, exposed_fields, required: [])
  end

  defp build_action_schema(_action, schema, exposed_fields, _writable, _introspection) do
    SchemaBuilder.build(schema, exposed_fields)
  end

  # Build description for action
  defp build_description(:list, resource_name, nil),
    do: "List all #{resource_name} records"

  defp build_description(:list, resource_name, namespace),
    do: "[#{namespace}] List all #{resource_name} records"

  defp build_description(:get, resource_name, nil),
    do: "Get a #{resource_name} by ID"

  defp build_description(:get, resource_name, namespace),
    do: "[#{namespace}] Get a #{resource_name} by ID"

  defp build_description(:create, resource_name, nil),
    do: "Create a new #{resource_name}"

  defp build_description(:create, resource_name, namespace),
    do: "[#{namespace}] Create a new #{resource_name}"

  defp build_description(:update, resource_name, nil),
    do: "Update an existing #{resource_name}"

  defp build_description(:update, resource_name, namespace),
    do: "[#{namespace}] Update an existing #{resource_name}"

  defp build_description(:destroy, resource_name, nil),
    do: "Delete a #{resource_name}"

  defp build_description(:destroy, resource_name, namespace),
    do: "[#{namespace}] Delete a #{resource_name}"

  defp build_description(action, resource_name, nil),
    do: "#{action} #{resource_name}"

  defp build_description(action, resource_name, namespace),
    do: "[#{namespace}] #{action} #{resource_name}"

  # Build params from input_schema
  defp build_params(input_schema) do
    properties = input_schema["properties"] || %{}
    required_fields = input_schema["required"] || []

    Enum.map(properties, fn {name_str, prop_schema} ->
      name = String.to_atom(name_str)
      type = json_schema_to_param_type(prop_schema)
      is_required = name_str in required_fields

      quote do
        param(unquote(name), unquote(type), required: unquote(is_required))
      end
    end)
  end

  @doc false
  defp json_schema_to_param_type(%{"type" => "array"}), do: {:array, :string}
  defp json_schema_to_param_type(%{"type" => "object"}), do: :map
  defp json_schema_to_param_type(%{"type" => "boolean"}), do: :boolean
  defp json_schema_to_param_type(%{"type" => "integer"}), do: :integer
  defp json_schema_to_param_type(%{"type" => "number"}), do: :float
  defp json_schema_to_param_type(_), do: :string
end
