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

  ## Examples

      expose MyApp.Accounts.User
      # Generates: list_users, get_user, create_user, update_user, destroy_user

      expose MyApp.Accounts.User, actions: [:list, :get]
      # Generates: list_users, get_user

      expose MyApp.Accounts.User, only: [:email, :name]
      # All tools only expose email and name fields
  """
  defmacro expose(schema_module, opts \\ []) do
    actions = Keyword.get(opts, :actions, [:list, :get, :create, :update, :destroy])
    only_fields = Keyword.get(opts, :only)
    except_fields = Keyword.get(opts, :except, [])

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
    resource_name =
      schema
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    # Generate tool definitions for each action
    tool_definitions =
      Enum.map(actions, fn action ->
        generate_tool_definition(
          action,
          resource_name,
          schema,
          exposed_fields,
          writable_fields,
          introspection
        )
      end)

    # Return all tool definitions
    quote do
      (unquote_splicing(tool_definitions))
    end
  end

  # Generate a single tool definition
  defp generate_tool_definition(
         action,
         resource_name,
         schema,
         exposed_fields,
         writable_fields,
         introspection
       ) do
    tool_name = build_tool_name(action, resource_name)

    input_schema =
      build_action_schema(action, schema, exposed_fields, writable_fields, introspection)

    description = build_description(action, resource_name)
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

  # Build tool name based on action
  defp build_tool_name(:list, resource_name), do: String.to_atom("list_#{resource_name}s")
  defp build_tool_name(:get, resource_name), do: String.to_atom("get_#{resource_name}")
  defp build_tool_name(:create, resource_name), do: String.to_atom("create_#{resource_name}")
  defp build_tool_name(:update, resource_name), do: String.to_atom("update_#{resource_name}")
  defp build_tool_name(:destroy, resource_name), do: String.to_atom("destroy_#{resource_name}")
  defp build_tool_name(action, resource_name), do: String.to_atom("#{action}_#{resource_name}")

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
  defp build_description(:list, resource_name), do: "List all #{resource_name} records"
  defp build_description(:get, resource_name), do: "Get a #{resource_name} by ID"
  defp build_description(:create, resource_name), do: "Create a new #{resource_name}"
  defp build_description(:update, resource_name), do: "Update an existing #{resource_name}"
  defp build_description(:destroy, resource_name), do: "Delete a #{resource_name}"
  defp build_description(action, resource_name), do: "#{action} #{resource_name}"

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
