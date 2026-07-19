if Code.ensure_loaded?(Ecto) do
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

      * `:actions` - List of actions to expose: `:list`, `:get`, `:create`, `:update`, `:destroy`, `:batch_create`, `:batch_update`, `:batch_destroy`
      * `:only` - Whitelist of fields to include
      * `:except` - Blacklist of fields to exclude
      * `:filterable` - Fields that allow advanced filter operators (defaults to all exposed fields)
      * `:namespace` - Prefix tools with namespace (e.g., `:accounts` → `accounts_list_users`)
      * `:as` - Alternative name for the resource (e.g., `:admin_users` → `list_admin_users`)
      * `:readonly` - Enable read-only mode (disables `:create`, `:update`, `:destroy`)
      * `:authorize` - Authorization configuration (function, policy module, or action-specific rules)
      * `:preload` - Ecto associations to eager-load on `:list` and `:get` results

    ## Generated Tools

    For a schema `MyApp.Accounts.User` with actions `[:list, :get, :create]`:

      * `list_users` - List all users with optional filters
      * `get_user` - Get a user by ID
      * `create_user` - Create a new user

    With batch actions `[:batch_create, :batch_update, :batch_destroy]`:

      * `batch_create_users` - Batch create users (array of records)
      * `batch_update_users` - Batch update users (array of records with IDs)
      * `batch_destroy_users` - Batch delete users (array of IDs)

    ## Field Filtering

    Fields can be filtered using `:only` or `:except`:

        # Only expose specific fields
        expose User, only: [:email, :name]

        # Exclude sensitive fields
        expose User, except: [:password_hash, :secret_token]

    ## Advanced Filtering Control

    By default, all exposed fields get advanced filter operators (`_gt`, `_contains`, etc.).
    Use `:filterable` to restrict which fields support these operators while still
    exposing all fields for reading:

        # Only allow advanced filtering on specific fields
        expose User,
          only: [:id, :email, :name, :role, :age],
          filterable: [:email, :age]
        # Email supports _contains, _icontains, etc.
        # Age supports _gt, _gte, _lt, _lte, etc.
        # Name and role only support exact-match filtering

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
      * `:batch_create` - Batch create records in a transaction, returns partial failures
      * `:batch_update` - Batch update records by primary key in a transaction
      * `:batch_destroy` - Batch delete records by primary key in a transaction

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

    alias Ectomancer.Authorization
    alias Ectomancer.Expose.Handlers
    alias Ectomancer.Expose.Params
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
      destroy: %{prefix: "destroy", suffix: "", description_template: "Delete a %{resource}"},
      restore: %{
        prefix: "restore",
        suffix: "",
        description_template: "Restore a soft-deleted %{resource}"
      },
      batch_create: %{
        prefix: "batch_create",
        suffix: "s",
        description_template: "Batch create %{resource}s"
      },
      batch_update: %{
        prefix: "batch_update",
        suffix: "s",
        description_template: "Batch update %{resource}s"
      },
      batch_destroy: %{
        prefix: "batch_destroy",
        suffix: "s",
        description_template: "Batch delete %{resource}s"
      },
      upsert: %{
        prefix: "upsert",
        suffix: "",
        description_template: "Create or update a %{resource} (upsert)"
      }
    }

    @doc """
    Exposes an Ecto schema as MCP tools.

    ## Parameters

      * `schema_module` - The Ecto schema module to expose
      * `opts` - Options for tool generation
        * `:actions` - List of actions (default: `[:list, :get, :create, :update, :destroy]`)
        * `:only` - Whitelist fields
        * `:except` - Blacklist fields
        * `:filterable` - Fields that allow advanced filter operators (default: all exposed fields)
        * `:readonly` - Disable mutation operations (`:create`, `:update`, `:destroy`)
        * `:namespace` - Prefix tools with namespace
        * `:as` - Alternative resource name
        * `:soft_delete` - Enable soft-delete awareness (auto-detects `:deleted_at`/`:archived_at` fields)
        * `:field_authorize` - Dynamic field-level authorization callback `fn actor, field -> boolean :: boolean()`

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

         expose MyApp.Accounts.User, filterable: [:email, :age]
         # Email and age support advanced filter operators;
         # all other exposed fields only support exact-match filtering.
    """
    defmacro expose(schema_module, opts \\ []) do
      schema = Macro.expand(schema_module, __CALLER__)

      # Compile-time validations and data extraction
      validate_schema_compiled!(schema)

      config = build_expose_config(schema, opts, Ectomancer.fetch_global_auth(__CALLER__.module))

      # Generate tool definitions for each action
      tool_definitions =
        Enum.map(config.actions, fn action ->
          tool_name = build_tool_name(action, config.resource_name, config.namespace)
          check_collision!(__CALLER__.module, tool_name)
          generate_tool(action, config, tool_name)
        end)

      # Generate MCP Resource module for schema discovery (opt-out with resource: false)
      resource_definitions =
        if config.resource do
          resource_prefix =
            if config.namespace,
              do: "#{config.namespace}_#{config.resource_name}",
              else: config.resource_name

          resource_module_name =
            Module.concat(__CALLER__.module, "Resource.#{Macro.camelize(resource_prefix)}")

          [generate_resource(config, resource_module_name, resource_prefix)]
        else
          []
        end

      quote do
        (unquote_splicing(tool_definitions ++ resource_definitions))
      end
    end

    # Configuration building

    defp build_expose_config(schema, opts, global_auth_raw) do
      introspection = SchemaIntrospection.analyze(schema)

      auth_explicitly_configured = Keyword.has_key?(opts, :authorize)
      auth_config = Authorization.parse_authorization_config(Keyword.get(opts, :authorize))
      parent_authorization = Authorization.parse_authorization_config(global_auth_raw)
      readonly = Keyword.get(opts, :readonly, false)

      base_actions = Keyword.get(opts, :actions, [:list, :get, :create, :update, :destroy])

      if :upsert in base_actions and not Keyword.has_key?(opts, :conflict_target) do
        raise ArgumentError,
              "`:conflict_target` is required when `:upsert` is in the actions list. " <>
                "Example: expose #{inspect(schema)}, actions: [:upsert], conflict_target: :email"
      end

      actions = filter_actions_for_readonly(base_actions, readonly)
      soft_delete = resolve_soft_delete(schema, opts)

      # Auto-add restore for soft-delete enabled schemas
      actions = if soft_delete, do: actions ++ [:restore], else: actions

      exposed_fields = filter_fields(introspection, opts)
      filterable_fields = filter_filterable_fields(exposed_fields, opts)

      %{
        schema: schema,
        actions: actions,
        exposed_fields: exposed_fields,
        filterable_fields: filterable_fields,
        writable_fields: filter_writable_fields(introspection, opts),
        resource_name: determine_resource_name(schema, opts[:as]),
        namespace: opts[:namespace],
        introspection: introspection,
        authorization: auth_config,
        parent_authorization: parent_authorization,
        auth_explicitly_configured: auth_explicitly_configured,
        readonly: readonly,
        preload: Keyword.get(opts, :preload, []),
        soft_delete: soft_delete,
        field_authorize: Keyword.get(opts, :field_authorize),
        repo: Keyword.get(opts, :repo),
        resource: Keyword.get(opts, :resource, true),
        preloadable: resolve_preloadable(introspection, opts),
        batch_size: Keyword.get(opts, :batch_size, 100),
        conflict_target: opts[:conflict_target],
        on_conflict: Keyword.get(opts, :on_conflict, :replace_all)
      }
    end

    defp resolve_preloadable(_introspection, opts) do
      case Keyword.get(opts, :preloadable) do
        nil -> false
        false -> false
        true -> :all
        assocs when is_list(assocs) -> assocs
      end
    end

    defp resolve_soft_delete(schema, opts) do
      case Keyword.get(opts, :soft_delete) do
        nil -> false
        false -> false
        true -> SchemaIntrospection.soft_delete_field(schema)
        field when is_atom(field) -> field
      end
    end

    defp filter_actions_for_readonly(actions, true) do
      Enum.filter(actions, fn action -> action in [:list, :get] end)
    end

    defp filter_actions_for_readonly(actions, _), do: actions

    @doc false
    def parse_auth_config(nil), do: nil
    def parse_auth_config(:none), do: nil
    def parse_auth_config(:public), do: nil
    def parse_auth_config(handler), do: Authorization.parse_handler_for_global(handler)

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

    defp filter_filterable_fields(exposed_fields, opts) do
      case Keyword.get(opts, :filterable) do
        nil -> exposed_fields
        fields when is_list(fields) -> Enum.filter(fields, fn f -> f in exposed_fields end)
      end
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

    # Resource generation for MCP schema discovery

    defp generate_resource(config, module_name, uri_key) do
      resource_name = config.resource_name
      schema = config.schema
      introspection = config.introspection
      actions = config.actions

      # Build metadata structures at compile time
      fields_meta =
        Enum.map(config.exposed_fields, fn field ->
          ecto_type = Map.get(introspection.types, field)

          %{
            "name" => Atom.to_string(field),
            "type" => SchemaIntrospection.type_to_string(ecto_type),
            "required" =>
              field not in config.writable_fields and field not in introspection.primary_key
          }
        end)

      assocs_meta =
        Enum.map(introspection.associations, fn assoc ->
          %{
            "name" => Atom.to_string(assoc.field),
            "type" => Atom.to_string(assoc.cardinality),
            "related" => inspect(assoc.related)
          }
        end)

      pk_meta = Enum.map(introspection.primary_key, &Atom.to_string/1)
      actions_meta = Enum.map(actions, &Atom.to_string/1)
      schema_module_str = inspect(schema)
      resource_uri = "ectomancer://schemas/#{uri_key}"

      resource_entry = %{
        "name" => resource_name,
        "uri" => resource_uri,
        "title" => "#{Macro.camelize(resource_name)} Schema"
      }

      quote do
        defmodule unquote(module_name) do
          use Anubis.Server.Component,
            type: :resource,
            uri: unquote(resource_uri),
            name: unquote(resource_name),
            mime_type: "application/json"

          @moduledoc "Schema metadata for #{unquote(resource_name)}"

          def description, do: "Schema metadata for #{unquote(resource_name)}"

          def read(_params, frame) do
            metadata = %{
              "name" => unquote(resource_name),
              "module" => unquote(schema_module_str),
              "uri" => unquote(resource_uri),
              "fields" => unquote(Macro.escape(fields_meta)),
              "associations" => unquote(Macro.escape(assocs_meta)),
              "primary_key" => unquote(Macro.escape(pk_meta)),
              "available_actions" => unquote(Macro.escape(actions_meta))
            }

            {:reply,
             %Anubis.Server.Response{
               type: :resource,
               content: [%{"type" => "text", "text" => Jason.encode!(metadata)}]
             }, frame}
          end
        end

        require Anubis.Server
        Anubis.Server.component(unquote(module_name))
        @ectomancer_resources unquote(Macro.escape(resource_entry))
      end
    end

    # Tool generation with proper param support
    # Params are now fully enabled with JSON Schema format for external communication
    # Validation is handled internally in Ectomancer.Repo

    defp generate_tool(action, config, tool_name) do
      description = build_description(action, config.resource_name, config.namespace)
      params = Params.generate_params(action, config)
      auth_block = generate_authorization_block(action, config)

      base_handler = Handlers.select(action, config)

      handler =
        if config.field_authorize do
          Handlers.wrap_with_field_auth(base_handler, config.field_authorize)
        else
          base_handler
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

    # Authorization block generation
    defp generate_authorization_block(action, config) do
      per_auth = config.authorization
      parent_auth = config.parent_authorization
      per_explicit? = config.auth_explicitly_configured
      do_generate_authorization_block(per_auth, parent_auth, action, per_explicit?)
    end

    defp get_effective_handler(nil, _action), do: nil

    defp get_effective_handler(%{global: global, actions: actions}, action)
         when map_size(actions) > 0 do
      case Map.get(actions, action) do
        :none -> nil
        :public -> nil
        nil -> global
        handler -> handler
      end
    end

    defp get_effective_handler(%{global: global}, _action), do: global

    defp do_generate_authorization_block(auth_config, parent_auth, action, per_explicit?) do
      per_handler = get_effective_handler(auth_config, action)
      global_handler = get_effective_handler(parent_auth, action)

      cond do
        # No auth anywhere
        is_nil(per_handler) and is_nil(global_handler) ->
          quote(do: authorize(:none))

        # Explicit opt-out via authorize: :none → public, skipping global
        is_nil(per_handler) and is_nil(auth_config) and per_explicit? ->
          quote(do: authorize(:none))

        # No per-schema handler → use global
        is_nil(per_handler) ->
          generate_single_auth(global_handler)

        # Only per-schema handler, no global
        is_nil(global_handler) ->
          generate_single_auth(per_handler)

        # Both present → cascade (both must pass)
        true ->
          generate_cascade_auth(per_handler, global_handler)
      end
    end

    defp generate_single_auth(:none), do: quote(do: authorize(:none))
    defp generate_single_auth(:public), do: quote(do: authorize(:none))

    defp generate_single_auth(handler) do
      handler_to_auth_ast(handler)
    end

    defp handler_to_auth_ast(module) when is_atom(module) do
      quote do
        authorize(with: unquote(module))
      end
    end

    defp handler_to_auth_ast(handler) when is_function(handler) do
      quote do
        authorize(unquote(handler))
      end
    end

    defp handler_to_auth_ast({:fn, _, _} = fn_ast) do
      quote do
        authorize(unquote(fn_ast))
      end
    end

    defp handler_to_auth_ast({:&, _, _} = capture_ast) do
      quote do
        authorize(unquote(capture_ast))
      end
    end

    defp handler_to_auth_ast(handler) do
      raise ArgumentError,
            "Invalid authorization handler: #{inspect(handler)}"
    end

    defp generate_cascade_auth(per_handler, global_handler) do
      per_ast = handler_to_raw_ast(per_handler)
      global_ast = handler_to_raw_ast(global_handler)

      quote do
        authorize(unquote(per_ast), parent_auth: unquote(global_ast))
      end
    end

    defp handler_to_raw_ast(module) when is_atom(module), do: {:with, [], [module]}
    defp handler_to_raw_ast({:fn, _, _} = fn_ast), do: fn_ast
    defp handler_to_raw_ast({:&, _, _} = capture_ast), do: capture_ast
    defp handler_to_raw_ast(handler) when is_function(handler), do: handler

    @doc false
    def get_ecto_type_for_param(:string), do: :string
    def get_ecto_type_for_param(:integer), do: :integer
    def get_ecto_type_for_param(:float), do: :float
    def get_ecto_type_for_param(:decimal), do: :float
    def get_ecto_type_for_param(:boolean), do: :boolean
    def get_ecto_type_for_param(:date), do: :string
    def get_ecto_type_for_param(:time), do: :string
    def get_ecto_type_for_param(:naive_datetime), do: :string
    def get_ecto_type_for_param(:utc_datetime), do: :string
    def get_ecto_type_for_param(:binary_id), do: :string
    def get_ecto_type_for_param(:id), do: :integer
    def get_ecto_type_for_param(Ecto.UUID), do: :string
    def get_ecto_type_for_param({:array, _}), do: :list
    def get_ecto_type_for_param(:map), do: :map
    def get_ecto_type_for_param(_), do: :string

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
else
  defmodule Ectomancer.Expose do
    @moduledoc false

    defmacro expose(_schema_module, _opts \\ []) do
      quote do
      end
    end
  end
end
