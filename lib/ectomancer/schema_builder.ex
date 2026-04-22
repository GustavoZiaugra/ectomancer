if Code.ensure_loaded?(Ecto) do
  defmodule Ectomancer.SchemaBuilder do
    @moduledoc """
    Converts Ecto types to MCP-compatible JSON Schema definitions.

    This module provides utilities to convert Ecto schema types into JSON Schema
    format suitable for MCP tool definitions.

    ## Example

        schema = Ectomancer.SchemaBuilder.build(MyApp.Accounts.User, [:email, :name, :age])
        # Returns: %{
        #   "type" => "object",
        #   "properties" => %{
        #     "email" => %{"type" => "string"},
        #     "name" => %{"type" => "string"},
        #     "age" => %{"type" => "integer"}
        #   },
        #   "required" => ["email", "name"]
        # }

    ## Type Mappings

    | Ecto Type | JSON Schema | Format |
    |-----------|-------------|--------|
    | `:string` | `"type" => "string"` | - |
    | `:integer` | `"type" => "integer"` | - |
    | `:float` / `:decimal` | `"type" => "number"` | - |
    | `:boolean` | `"type" => "boolean"` | - |
    | `:date` | `"type" => "string"` | `"date"` |
    | `:time` | `"type" => "string"` | `"time"` |
    | `:naive_datetime` | `"type" => "string"` | `"date-time"` |
    | `:utc_datetime` | `"type" => "string"` | `"date-time"` |
    | `Ecto.UUID` | `"type" => "string"` | `"uuid"` |
    | `{:array, inner}` | `"type" => "array"` | items schema |
    | `:map` / embeds | `"type" => "object"` | - |
    """

    alias Ectomancer.SchemaIntrospection

    @doc """
    Builds a JSON Schema for the given fields of a schema.

    ## Parameters

      * `schema_module` - The Ecto schema module
      * `fields` - List of field names to include (defaults to all writable fields)
      * `opts` - Options for schema generation
        * `:required` - List of required fields (defaults to non-nullable fields)
        * `:nullable` - Whether to mark all fields as nullable (default: false)

    ## Returns

      A JSON Schema map with "type", "properties", and optionally "required" keys.

    ## Examples

        iex> Ectomancer.SchemaBuilder.build(MyApp.Accounts.User, [:email, :name])
        %{
          "type" => "object",
          "properties" => %{
            "email" => %{"type" => "string"},
            "name" => %{"type" => "string"}
          },
          "required" => ["email"]
        }
    """
    # Allow nil for fields parameter to use default writable fields
    @spec build(module(), [atom()] | nil, keyword()) :: map()
    def build(schema_module, fields \\ nil, opts \\ []) do
      fields = fields || SchemaIntrospection.writable_fields(schema_module)
      introspection = SchemaIntrospection.analyze(schema_module)

      properties =
        Map.new(fields, fn field ->
          type = introspection.types[field]
          schema = type_to_schema(type)
          {to_string(field), schema}
        end)

      required_fields =
        case opts[:required] do
          nil ->
            # Auto-detect required fields based on type (exclude nilable)
            fields
            |> Enum.reject(fn field ->
              type = introspection.types[field]
              # Consider fields with {:maybe, _} type or default values as optional
              is_nil(type) or
                (is_tuple(type) and elem(type, 0) == :maybe)
            end)
            |> Enum.map(&to_string/1)

          explicit_required ->
            Enum.map(explicit_required, &to_string/1)
        end

      schema = %{
        "type" => "object",
        "properties" => properties
      }

      if required_fields != [] do
        Map.put(schema, "required", required_fields)
      else
        schema
      end
    end

    @doc """
    Converts an Ecto type to a JSON Schema definition.

    ## Examples

        iex> Ectomancer.SchemaBuilder.type_to_schema(:string)
        %{"type" => "string"}

        iex> Ectomancer.SchemaBuilder.type_to_schema(:date)
        %{"type" => "string", "format" => "date"}

        iex> Ectomancer.SchemaBuilder.type_to_schema({:array, :string})
        %{"type" => "array", "items" => %{"type" => "string"}}
    """
    @simple_type_schemas %{
      :string => %{"type" => "string"},
      :integer => %{"type" => "integer"},
      :float => %{"type" => "number"},
      :decimal => %{"type" => "number"},
      :boolean => %{"type" => "boolean"},
      :id => %{"type" => "integer"},
      :binary_id => %{"type" => "string"},
      :map => %{"type" => "object"}
    }

    @formatted_types %{
      :date => "date",
      :time => "time",
      :time_usec => "time",
      :naive_datetime => "date-time",
      :naive_datetime_usec => "date-time",
      :utc_datetime => "date-time",
      :utc_datetime_usec => "date-time"
    }

    @spec type_to_schema(any()) :: map()
    def type_to_schema(type) do
      case type do
        {:array, inner_type} ->
          %{"type" => "array", "items" => type_to_schema(inner_type)}

        %Ecto.Embedded{} = embed ->
          build(embed.related) |> Map.put("type", "object")

        Ecto.UUID ->
          %{"type" => "string", "format" => "uuid"}

        :binary ->
          %{"type" => "string", "contentEncoding" => "base64"}

        _ ->
          cond do
            schema = @simple_type_schemas[type] ->
              schema

            format = @formatted_types[type] ->
              %{"type" => "string", "format" => format}

            true ->
              %{"type" => "string"}
          end
      end
    end

    @doc """
    Builds a JSON Schema for a specific action (create, update, etc.).

    Different actions may have different required fields or include/exclude
    certain fields.

    ## Examples

        iex> Ectomancer.SchemaBuilder.build_for_action(MyApp.Accounts.User, :create)
        # Returns schema with all writable fields, required based on nullability

        iex> Ectomancer.SchemaBuilder.build_for_action(MyApp.Accounts.User, :update)
        # Returns schema with all writable fields, none required (partial updates)
    """
    @spec build_for_action(module(), atom(), keyword()) :: map()
    def build_for_action(schema_module, action, opts \\ []) do
      base_fields = SchemaIntrospection.writable_fields(schema_module)

      {fields, required} =
        case action do
          :create ->
            # For create, use all writable fields with auto-required
            {base_fields, nil}

          :update ->
            # For update, all fields are optional (partial updates allowed)
            {base_fields, []}

          :get ->
            # For get, only need primary key
            pk = SchemaIntrospection.primary_key(schema_module)
            {pk, Enum.map(pk, &to_string/1)}

          :list ->
            # For list, optional filter fields
            {base_fields, []}

          :destroy ->
            # For destroy, only need primary key
            pk = SchemaIntrospection.primary_key(schema_module)
            {pk, Enum.map(pk, &to_string/1)}

          _ ->
            {base_fields, nil}
        end

      build(schema_module, fields, Keyword.put(opts, :required, required))
    end
  end
else
  defmodule Ectomancer.SchemaBuilder do
    @moduledoc false
  end
end
