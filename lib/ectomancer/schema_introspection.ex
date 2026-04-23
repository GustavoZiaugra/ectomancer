if Code.ensure_loaded?(Ecto) do
  defmodule Ectomancer.SchemaIntrospection do
    @moduledoc """
    Compile-time Ecto schema introspection for generating MCP tools.

    This module provides utilities to read Ecto schema metadata at compile time
    and use it to generate MCP-compatible tool definitions.

    ## Example

        schema_info = Ectomancer.SchemaIntrospection.analyze(MyApp.Accounts.User)
        # Returns: %{
        #   fields: [:id, :email, :name, :inserted_at, :updated_at],
        #   types: %{id: :id, email: :string, name: :string, ...},
        #   associations: [%{field: :posts, cardinality: :many, related: MyApp.Blog.Post}],
        #   primary_key: [:id]
        # }

    ## Supported Ecto Types

    - `:string` - String values
    - `:integer` - Integer values
    - `:float` / `:decimal` - Number values
    - `:boolean` - Boolean values
    - `:date` - Date values
    - `:time` / `:time_usec` - Time values
    - `:naive_datetime` / `:naive_datetime_usec` - Naive datetime values
    - `:utc_datetime` / `:utc_datetime_usec` - UTC datetime values
    - `Ecto.UUID` - UUID values
    - `{:array, inner}` - Array values
    - `:map` - Map/object values
    - Embeds - Embedded schemas
    """

    @doc """
    Analyzes an Ecto schema module and returns its metadata.

    ## Parameters

      * `schema_module` - The Ecto schema module to analyze

    ## Returns

      A map containing:
      * `:fields` - List of field names (atoms)
      * `:types` - Map of field names to their Ecto types
      * `:associations` - List of association information
      * `:primary_key` - List of primary key field names
      * `:embedded` - Boolean indicating if this is an embedded schema

    ## Examples

        iex> Ectomancer.SchemaIntrospection.analyze(MyApp.Accounts.User)
        %{
          fields: [:id, :email, :name, :role, :inserted_at, :updated_at],
          types: %{
            id: :id,
            email: :string,
            name: :string,
            role: :string,
            inserted_at: :utc_datetime,
            updated_at: :utc_datetime
          },
          associations: [
            %{field: :posts, cardinality: :many, related: MyApp.Blog.Post}
          ],
          primary_key: [:id],
          embedded: false
        }
    """
    @spec analyze(module()) :: %{
            fields: [atom()],
            types: %{atom() => any()},
            associations: [%{field: atom(), cardinality: atom(), related: module()}],
            primary_key: [atom()],
            embedded: boolean()
          }
    def analyze(schema_module) do
      unless ecto_schema?(schema_module) do
        raise ArgumentError,
              "#{inspect(schema_module)} is not an Ecto schema. " <>
                "Make sure it uses Ecto.Schema and defines a schema block."
      end

      fields = schema_module.__schema__(:fields)
      types = Map.new(fields, fn field -> {field, schema_module.__schema__(:type, field)} end)
      associations = get_associations(schema_module)
      primary_key = schema_module.__schema__(:primary_key)

      # Check if this is an embedded schema (embedded schemas don't have :embedded function)
      embedded =
        try do
          schema_module.__schema__(:embedded)
        rescue
          _ -> false
        end

      %{
        fields: fields,
        types: types,
        associations: associations,
        primary_key: primary_key,
        embedded: embedded
      }
    end

    @doc """
    Returns true if the module is an Ecto schema.

    ## Examples

        iex> Ectomancer.SchemaIntrospection.ecto_schema?(MyApp.Accounts.User)
        true

        iex> Ectomancer.SchemaIntrospection.ecto_schema?(String)
        false
    """
    @spec ecto_schema?(module()) :: boolean()
    def ecto_schema?(module) do
      Code.ensure_loaded?(module) and
        function_exported?(module, :__schema__, 1)
    end

    @doc """
    Gets all associations for a schema module.

    Returns a list of maps with association metadata.
    """
    @spec get_associations(module()) :: [%{field: atom(), cardinality: atom(), related: module()}]
    def get_associations(schema_module) do
      schema_module.__schema__(:associations)
      |> Enum.map(fn assoc_field ->
        assoc = schema_module.__schema__(:association, assoc_field)

        %{
          field: assoc_field,
          cardinality: assoc.cardinality,
          related: assoc.related
        }
      end)
    end

    @doc """
    Gets field information including type and nullable status.

    ## Examples

        iex> Ectomancer.SchemaIntrospection.field_info(MyApp.Accounts.User, :email)
        %{type: :string, nullable: false}
    """
    @spec field_info(module(), atom()) :: %{type: any(), nullable: boolean()}
    def field_info(schema_module, field) do
      type = schema_module.__schema__(:type, field)

      # Check if field is nullable by looking at the type
      # Nullable fields in Ecto typically have {:maybe, type} or are virtual
      nullable =
        case type do
          nil -> true
          _ -> false
        end

      %{type: type, nullable: nullable}
    end

    @doc """
    Returns the primary key field(s) for a schema.

    ## Examples

        iex> Ectomancer.SchemaIntrospection.primary_key(MyApp.Accounts.User)
        [:id]

        iex> Ectomancer.SchemaIntrospection.primary_key(MyApp.CompositeKeyModel)
        [:org_id, :user_id]
    """
    @spec primary_key(module()) :: [atom()]
    def primary_key(schema_module) do
      schema_module.__schema__(:primary_key)
    end

    @doc """
    Returns all fields except associations and primary key fields.

    Useful for generating create/update forms.

    ## Examples

        iex> Ectomancer.SchemaIntrospection.writable_fields(MyApp.Accounts.User)
        [:email, :name, :role]
    """
    @type_mapping %{
      :string => "string",
      :integer => "integer",
      :float => "float",
      :decimal => "decimal",
      :boolean => "boolean",
      :date => "date",
      :time => "time",
      :time_usec => "time",
      :naive_datetime => "datetime",
      :naive_datetime_usec => "datetime",
      :utc_datetime => "datetime",
      :utc_datetime_usec => "datetime",
      :id => "id",
      :binary_id => "binary_id",
      :binary => "binary",
      :map => "map"
    }

    @spec writable_fields(module()) :: [atom()]
    def writable_fields(schema_module) do
      introspection = analyze(schema_module)

      introspection.fields
      |> Enum.reject(fn field ->
        field in introspection.primary_key or
          field in [:inserted_at, :updated_at]
      end)
    end

    @doc """
    Converts an Ecto type to a human-readable string representation.

    ## Examples

        iex> Ectomancer.SchemaIntrospection.type_to_string(:string)
        "string"

        iex> Ectomancer.SchemaIntrospection.type_to_string({:array, :string})
        "array of string"

        iex> Ectomancer.SchemaIntrospection.type_to_string(Ecto.UUID)
        "uuid"
    """
    @spec type_to_string(any()) :: String.t()
    def type_to_string(type) do
      case type do
        {:array, inner} ->
          "array of #{type_to_string(inner)}"

        %Ecto.Embedded{} = embed ->
          "embed of #{embed.related}"

        module when is_atom(module) ->
          case Map.get(@type_mapping, module) do
            nil ->
              try do
                module |> Module.split() |> List.last() |> Macro.underscore()
              rescue
                _ ->
                  # Not a real module, just return the atom as string
                  Atom.to_string(module)
              end

            mapped ->
              mapped
          end

        _ ->
          "unknown"
      end
    end
  end
else
  defmodule Ectomancer.SchemaIntrospection do
    @moduledoc false

    def ecto_schema?(_module), do: false

    def analyze(_schema_module),
      do: %{fields: [], types: %{}, associations: [], primary_key: [], embedded: false}

    def get_associations(_schema_module), do: []
    def field_info(_schema_module, _field), do: %{type: nil, nullable: true}
    def primary_key(_schema_module), do: []
    def writable_fields(_schema_module), do: []
    def type_to_string(_type), do: "unknown"
  end
end
