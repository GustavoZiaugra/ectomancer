defmodule Ectomancer.SchemaIntrospectionTest do
  use ExUnit.Case

  alias Ectomancer.SchemaIntrospection

  # Define test Ecto schemas
  defmodule TestUser do
    use Ecto.Schema

    schema "users" do
      field(:email, :string)
      field(:name, :string)
      field(:age, :integer)
      field(:active, :boolean)
      field(:score, :float)
      field(:settings, :map)
      field(:tags, {:array, :string})
      field(:birth_date, :date)
      field(:last_login, :utc_datetime)

      timestamps()
    end
  end

  defmodule TestPost do
    use Ecto.Schema

    schema "posts" do
      field(:title, :string)
      field(:content, :string)
      field(:published, :boolean, default: false)

      belongs_to(:author, TestUser)
      has_many(:comments, TestComment)

      timestamps()
    end
  end

  defmodule TestComment do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:body, :string)
      field(:rating, :integer)
    end
  end

  defmodule NotASchema do
    def some_function, do: :ok
  end

  describe "analyze/1" do
    test "analyzes a simple schema" do
      info = SchemaIntrospection.analyze(TestUser)

      assert is_list(info.fields)
      assert :email in info.fields
      assert :name in info.fields
      assert is_map(info.types)
      assert info.types.email == :string
      assert info.types.age == :integer
      assert info.primary_key == [:id]
      assert info.embedded == false
    end

    test "analyzes schema with associations" do
      info = SchemaIntrospection.analyze(TestPost)

      assert length(info.associations) == 2

      author_assoc = Enum.find(info.associations, &(&1.field == :author))
      assert author_assoc.cardinality == :one
      # Check that related is a module
      assert is_atom(author_assoc.related)

      comments_assoc = Enum.find(info.associations, &(&1.field == :comments))
      assert comments_assoc.cardinality == :many
      # Check that related is a module
      assert is_atom(comments_assoc.related)
    end

    test "analyzes embedded schema" do
      info = SchemaIntrospection.analyze(TestComment)

      # Embedded schemas don't have a primary key
      assert info.primary_key == []
      assert :body in info.fields
      assert info.types.body == :string
    end

    test "raises for non-schema modules" do
      assert_raise ArgumentError, fn ->
        SchemaIntrospection.analyze(NotASchema)
      end
    end

    test "includes all field types" do
      info = SchemaIntrospection.analyze(TestUser)

      assert info.types.email == :string
      assert info.types.age == :integer
      assert info.types.active == :boolean
      assert info.types.score == :float
      assert info.types.settings == :map
      assert info.types.tags == {:array, :string}
      assert info.types.birth_date == :date
      assert info.types.last_login == :utc_datetime
    end

    test "includes timestamps" do
      info = SchemaIntrospection.analyze(TestUser)

      assert :inserted_at in info.fields
      assert :updated_at in info.fields
      assert info.types.inserted_at == :naive_datetime
    end
  end

  describe "ecto_schema?/1" do
    test "returns true for Ecto schemas" do
      assert SchemaIntrospection.ecto_schema?(TestUser) == true
      assert SchemaIntrospection.ecto_schema?(TestPost) == true
      assert SchemaIntrospection.ecto_schema?(TestComment) == true
    end

    test "returns false for non-schema modules" do
      assert SchemaIntrospection.ecto_schema?(NotASchema) == false
      assert SchemaIntrospection.ecto_schema?(String) == false
    end
  end

  describe "get_associations/1" do
    test "returns associations list" do
      associations = SchemaIntrospection.get_associations(TestPost)

      assert length(associations) == 2
      fields = Enum.map(associations, & &1.field)
      assert :author in fields
      assert :comments in fields
    end

    test "returns empty list for schema without associations" do
      associations = SchemaIntrospection.get_associations(TestUser)
      assert associations == []
    end
  end

  describe "field_info/2" do
    test "returns field type and nullable status" do
      info = SchemaIntrospection.field_info(TestUser, :email)

      assert info.type == :string
      assert info.nullable == false
    end

    test "returns nil type for non-existent field" do
      info = SchemaIntrospection.field_info(TestUser, :non_existent)

      assert info.type == nil
      assert info.nullable == true
    end
  end

  describe "primary_key/1" do
    test "returns primary key fields" do
      assert SchemaIntrospection.primary_key(TestUser) == [:id]
      assert SchemaIntrospection.primary_key(TestPost) == [:id]
    end

    test "returns empty list for schema without primary key" do
      assert SchemaIntrospection.primary_key(TestComment) == []
    end
  end

  describe "writable_fields/1" do
    test "excludes primary key and timestamps" do
      fields = SchemaIntrospection.writable_fields(TestUser)

      refute :id in fields
      refute :inserted_at in fields
      refute :updated_at in fields

      assert :email in fields
      assert :name in fields
      assert :age in fields
    end
  end

  describe "type_to_string/1" do
    test "converts basic types" do
      assert SchemaIntrospection.type_to_string(:string) == "string"
      assert SchemaIntrospection.type_to_string(:integer) == "integer"
      assert SchemaIntrospection.type_to_string(:float) == "float"
      assert SchemaIntrospection.type_to_string(:boolean) == "boolean"
      assert SchemaIntrospection.type_to_string(:date) == "date"
    end

    test "converts datetime types" do
      assert SchemaIntrospection.type_to_string(:naive_datetime) == "datetime"
      assert SchemaIntrospection.type_to_string(:utc_datetime) == "datetime"
      assert SchemaIntrospection.type_to_string(:naive_datetime_usec) == "datetime"
      assert SchemaIntrospection.type_to_string(:utc_datetime_usec) == "datetime"
    end

    test "converts array types" do
      assert SchemaIntrospection.type_to_string({:array, :string}) == "array of string"
      assert SchemaIntrospection.type_to_string({:array, :integer}) == "array of integer"
    end

    test "converts nested arrays" do
      assert SchemaIntrospection.type_to_string({:array, {:array, :string}}) ==
               "array of array of string"
    end

    test "converts UUID module" do
      assert SchemaIntrospection.type_to_string(Ecto.UUID) == "uuid"
    end

    test "handles unknown types" do
      # Unknown atom types return the atom as string
      assert SchemaIntrospection.type_to_string(:unknown_type) == "unknown_type"
      # Nil returns nil as string
      assert SchemaIntrospection.type_to_string(nil) == "nil"
    end
  end
end
