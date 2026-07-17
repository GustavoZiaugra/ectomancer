defmodule Ectomancer.DataCase do
  @moduledoc """
  Test case for database-backed integration tests.

  Provides table creation and data insertion helpers for tests
  that run against the in-memory SQLite TestRepo.
  """

  use ExUnit.CaseTemplate

  @compile {:no_warn_undefined, {Ectomancer.TestRepo, :insert_all, 3}}

  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox
  alias Ectomancer.TestRepo

  using do
    quote do
      alias Ectomancer.TestRepo
      import Ectomancer.DataCase
    end
  end

  setup tags do
    :ok = Sandbox.checkout(TestRepo)

    unless tags[:async] do
      Sandbox.mode(TestRepo, {:shared, self()})
    end

    # Create tables for schemas listed in the @moduletag :schemas
    schema_modules = Map.get(tags, :schemas, [])

    for schema <- schema_modules do
      create_table_for_schema!(schema)
    end

    {:ok, repo: TestRepo}
  end

  @doc """
  Creates a temporary table for the given Ecto schema.
  """
  def create_table_for_schema!(schema_module) do
    table_name = schema_module.__schema__(:source)
    fields = schema_module.__schema__(:fields)

    columns =
      Enum.map(fields, fn field ->
        type = schema_module.__schema__(:type, field)
        sql_type = ecto_type_to_sql(type)

        if field in schema_module.__schema__(:primary_key) do
          "#{field} #{sql_type} PRIMARY KEY"
        else
          "#{field} #{sql_type}"
        end
      end)

    SQL.query!(TestRepo, "CREATE TABLE #{table_name} (#{Enum.join(columns, ",")})")
  end

  defp ecto_type_to_sql(:id), do: "INTEGER"
  defp ecto_type_to_sql(:integer), do: "INTEGER"
  defp ecto_type_to_sql(:string), do: "TEXT"
  defp ecto_type_to_sql(:text), do: "TEXT"
  defp ecto_type_to_sql(:boolean), do: "INTEGER"
  defp ecto_type_to_sql(:float), do: "REAL"
  defp ecto_type_to_sql(:decimal), do: "REAL"
  defp ecto_type_to_sql(:date), do: "TEXT"
  defp ecto_type_to_sql(:time), do: "TEXT"
  defp ecto_type_to_sql(:naive_datetime), do: "TEXT"
  defp ecto_type_to_sql(:utc_datetime), do: "TEXT"
  defp ecto_type_to_sql(:binary_id), do: "TEXT"
  defp ecto_type_to_sql(Ecto.UUID), do: "TEXT"
  defp ecto_type_to_sql({:array, _}), do: "TEXT"
  defp ecto_type_to_sql(:map), do: "TEXT"
  defp ecto_type_to_sql(_), do: "TEXT"

  @doc """
  Inserts a single record using Ecto's type casting.

  Automatically populates `inserted_at` and `updated_at` if the schema
  has timestamps and they are not provided.
  """
  def insert!(schema_module, attrs) when is_map(attrs) or is_list(attrs) do
    attrs =
      case schema_module.__schema__(:fields) do
        fields when is_list(fields) ->
          now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

          attrs
          |> Enum.into(%{})
          |> maybe_put_timestamp(:inserted_at, fields, now)
          |> maybe_put_timestamp(:updated_at, fields, now)

        _ ->
          attrs
      end

    {1, _} = TestRepo.insert_all(schema_module, [attrs], [])
    :ok
  end

  defp maybe_put_timestamp(attrs, field, fields, value) do
    if field in fields and not Map.has_key?(attrs, field) do
      Map.put(attrs, field, value)
    else
      attrs
    end
  end

  @doc """
  Creates a unique index on the given fields for a schema's table.

  Used by upsert tests to enforce uniqueness on conflict target fields.

  ## Examples

      Ectomancer.DataCase.create_unique_index!(MyApp.Accounts.User, :email)
      Ectomancer.DataCase.create_unique_index!(MyApp.Accounts.User, [:org_id, :sku])
  """
  def create_unique_index!(schema_module, fields) do
    table_name = schema_module.__schema__(:source)
    fields_list = List.wrap(fields)
    index_name = "#{table_name}_#{Enum.map_join(fields_list, "_", &to_string/1)}_unique"
    cols = Enum.map_join(fields_list, ", ", &to_string/1)

    SQL.query!(TestRepo, "CREATE UNIQUE INDEX #{index_name} ON #{table_name} (#{cols})")
  end

  @doc """
  Counts records in a schema's table.
  """
  def count(schema_module) do
    table = schema_module.__schema__(:source)
    %{rows: [[count]]} = SQL.query!(TestRepo, "SELECT COUNT(*) FROM #{table}")
    count
  end
end
