defmodule Ectomancer.SchemaBuilderTest do
  use ExUnit.Case

  alias Ectomancer.SchemaBuilder

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

    @primary_key {:id, Ecto.UUID, autogenerate: true}

    schema "posts" do
      field(:title, :string)
      field(:content, :string)
      field(:published, :boolean, default: false)

      timestamps()
    end
  end

  describe "build/3" do
    test "builds schema for simple fields" do
      schema = SchemaBuilder.build(TestUser, [:email, :name])

      assert schema["type"] == "object"
      assert schema["properties"]["email"]["type"] == "string"
      assert schema["properties"]["name"]["type"] == "string"
    end

    test "builds schema with all field types" do
      schema = SchemaBuilder.build(TestUser)

      # Check all field types are correctly mapped
      assert schema["properties"]["email"]["type"] == "string"
      assert schema["properties"]["age"]["type"] == "integer"
      assert schema["properties"]["active"]["type"] == "boolean"
      assert schema["properties"]["score"]["type"] == "number"
      assert schema["properties"]["settings"]["type"] == "object"
      assert schema["properties"]["tags"]["type"] == "array"
      assert schema["properties"]["birth_date"]["type"] == "string"
      assert schema["properties"]["birth_date"]["format"] == "date"
      assert schema["properties"]["last_login"]["type"] == "string"
      assert schema["properties"]["last_login"]["format"] == "date-time"
    end

    test "excludes id and timestamps by default" do
      schema = SchemaBuilder.build(TestUser)

      refute Map.has_key?(schema["properties"], "id")
      refute Map.has_key?(schema["properties"], "inserted_at")
      refute Map.has_key?(schema["properties"], "updated_at")
    end

    test "supports explicit required fields" do
      schema = SchemaBuilder.build(TestUser, [:email, :name], required: [:email])

      assert schema["required"] == ["email"]
    end

    test "supports empty required fields" do
      schema = SchemaBuilder.build(TestUser, [:email, :name], required: [])

      refute Map.has_key?(schema, "required")
    end
  end

  describe "type_to_schema/1" do
    test "converts :string to string schema" do
      assert SchemaBuilder.type_to_schema(:string) == %{"type" => "string"}
    end

    test "converts :integer to integer schema" do
      assert SchemaBuilder.type_to_schema(:integer) == %{"type" => "integer"}
    end

    test "converts :float to number schema" do
      assert SchemaBuilder.type_to_schema(:float) == %{"type" => "number"}
    end

    test "converts :decimal to number schema" do
      assert SchemaBuilder.type_to_schema(:decimal) == %{"type" => "number"}
    end

    test "converts :boolean to boolean schema" do
      assert SchemaBuilder.type_to_schema(:boolean) == %{"type" => "boolean"}
    end

    test "converts :date to date schema" do
      schema = SchemaBuilder.type_to_schema(:date)
      assert schema["type"] == "string"
      assert schema["format"] == "date"
    end

    test "converts :utc_datetime to date-time schema" do
      schema = SchemaBuilder.type_to_schema(:utc_datetime)
      assert schema["type"] == "string"
      assert schema["format"] == "date-time"
    end

    test "converts :naive_datetime to date-time schema" do
      schema = SchemaBuilder.type_to_schema(:naive_datetime)
      assert schema["type"] == "string"
      assert schema["format"] == "date-time"
    end

    test "converts :id to integer schema" do
      assert SchemaBuilder.type_to_schema(:id) == %{"type" => "integer"}
    end

    test "converts :binary_id to string schema" do
      assert SchemaBuilder.type_to_schema(:binary_id) == %{"type" => "string"}
    end

    test "converts Ecto.UUID to uuid schema" do
      schema = SchemaBuilder.type_to_schema(Ecto.UUID)
      assert schema["type"] == "string"
      assert schema["format"] == "uuid"
    end

    test "converts :binary to base64 string schema" do
      schema = SchemaBuilder.type_to_schema(:binary)
      assert schema["type"] == "string"
      assert schema["contentEncoding"] == "base64"
    end

    test "converts :map to object schema" do
      assert SchemaBuilder.type_to_schema(:map) == %{"type" => "object"}
    end

    test "converts {:array, inner} to array schema" do
      schema = SchemaBuilder.type_to_schema({:array, :string})
      assert schema["type"] == "array"
      assert schema["items"]["type"] == "string"
    end

    test "converts nested arrays" do
      schema = SchemaBuilder.type_to_schema({:array, {:array, :integer}})
      assert schema["type"] == "array"
      assert schema["items"]["type"] == "array"
      assert schema["items"]["items"]["type"] == "integer"
    end

    test "defaults unknown types to string" do
      assert SchemaBuilder.type_to_schema(:unknown_type) == %{"type" => "string"}
    end
  end

  describe "build_for_action/3" do
    test ":create action includes all writable fields" do
      schema = SchemaBuilder.build_for_action(TestUser, :create)

      assert Map.has_key?(schema["properties"], "email")
      assert Map.has_key?(schema["properties"], "name")
      assert Map.has_key?(schema["properties"], "age")
    end

    test ":update action makes all fields optional" do
      schema = SchemaBuilder.build_for_action(TestUser, :update)

      # Update should have empty required list
      refute Map.has_key?(schema, "required")
    end

    test ":get action only includes primary key" do
      schema = SchemaBuilder.build_for_action(TestUser, :get)

      assert Map.keys(schema["properties"]) == ["id"]
      assert schema["required"] == ["id"]
    end

    test ":list action includes filter fields" do
      schema = SchemaBuilder.build_for_action(TestUser, :list)

      assert Map.has_key?(schema["properties"], "email")
      assert Map.has_key?(schema["properties"], "name")
    end

    test ":destroy action only includes primary key" do
      schema = SchemaBuilder.build_for_action(TestUser, :destroy)

      assert Map.keys(schema["properties"]) == ["id"]
      assert schema["required"] == ["id"]
    end
  end

  describe "UUID primary keys" do
    test "handles Ecto.UUID primary key" do
      schema = SchemaBuilder.build_for_action(TestPost, :get)

      assert schema["properties"]["id"]["type"] == "string"
      assert schema["properties"]["id"]["format"] == "uuid"
    end
  end
end
