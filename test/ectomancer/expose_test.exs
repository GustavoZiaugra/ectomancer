defmodule Ectomancer.ExposeTest do
  use ExUnit.Case

  defmodule TestUserSchema do
    use Ecto.Schema

    schema "users" do
      field(:email, :string)
      field(:name, :string)
      field(:age, :integer)
      field(:password_hash, :string)

      timestamps()
    end
  end

  defmodule TestMCP do
    use Ectomancer, name: "test-mcp", version: "1.0.0"

    expose(TestUserSchema, actions: [:list, :get, :create])
  end

  defmodule TestMCPFiltered do
    use Ectomancer, name: "test-filtered-mcp", version: "1.0.0"

    expose(TestUserSchema,
      actions: [:list, :get],
      except: [:password_hash]
    )
  end

  defmodule TestMCPOnly do
    use Ectomancer, name: "test-only-mcp", version: "1.0.0"

    expose(TestUserSchema,
      actions: [:create],
      only: [:email, :name]
    )
  end

  describe "expose/2 macro" do
    test "generates list_test_user_schemas tool" do
      assert Code.ensure_loaded?(TestMCP.Tool.ListTestUserSchemas)
    end

    test "generates get_test_user_schema tool" do
      assert Code.ensure_loaded?(TestMCP.Tool.GetTestUserSchema)
    end

    test "generates create_test_user_schema tool" do
      assert Code.ensure_loaded?(TestMCP.Tool.CreateTestUserSchema)
    end

    test "does not generate update_test_user_schema tool (not in actions)" do
      refute Code.ensure_loaded?(TestMCP.Tool.UpdateTestUserSchema)
    end

    test "does not generate destroy_test_user_schema tool (not in actions)" do
      refute Code.ensure_loaded?(TestMCP.Tool.DestroyTestUserSchema)
    end
  end

  describe "list_test_user_schemas tool" do
    test "has correct name" do
      assert TestMCP.Tool.ListTestUserSchemas.name() == "list_test_user_schemas"
    end

    test "has input schema with filter fields" do
      schema = TestMCP.Tool.ListTestUserSchemas.input_schema()

      assert schema["type"] == "object"
      # Should have email, name, age (not id, password_hash, timestamps)
      assert Map.has_key?(schema["properties"], "email")
      assert Map.has_key?(schema["properties"], "name")
      assert Map.has_key?(schema["properties"], "age")
    end

    test "all fields are optional for list" do
      schema = TestMCP.Tool.ListTestUserSchemas.input_schema()

      # No required fields for list action
      refute Map.has_key?(schema, "required")
    end
  end

  describe "get_test_user_schema tool" do
    test "has correct name" do
      assert TestMCP.Tool.GetTestUserSchema.name() == "get_test_user_schema"
    end

    test "only has id field" do
      schema = TestMCP.Tool.GetTestUserSchema.input_schema()

      assert Map.keys(schema["properties"]) == ["id"]
    end

    test "id is required" do
      schema = TestMCP.Tool.GetTestUserSchema.input_schema()

      assert schema["required"] == ["id"]
    end
  end

  describe "create_test_user_schema tool" do
    test "has correct name" do
      assert TestMCP.Tool.CreateTestUserSchema.name() == "create_test_user_schema"
    end

    test "has writable fields" do
      schema = TestMCP.Tool.CreateTestUserSchema.input_schema()

      # Should have writable fields (not id or timestamps)
      assert Map.has_key?(schema["properties"], "email")
      assert Map.has_key?(schema["properties"], "name")
      assert Map.has_key?(schema["properties"], "age")
      refute Map.has_key?(schema["properties"], "id")
      refute Map.has_key?(schema["properties"], "inserted_at")
      refute Map.has_key?(schema["properties"], "updated_at")
    end
  end

  describe "field filtering with except" do
    test "excludes password_hash from list" do
      schema = TestMCPFiltered.Tool.ListTestUserSchemas.input_schema()

      refute Map.has_key?(schema["properties"], "password_hash")
      assert Map.has_key?(schema["properties"], "email")
    end

    test "excludes password_hash from get" do
      schema = TestMCPFiltered.Tool.GetTestUserSchema.input_schema()

      # Get only has id anyway
      assert Map.keys(schema["properties"]) == ["id"]
    end
  end

  describe "field filtering with only" do
    test "only includes specified fields" do
      schema = TestMCPOnly.Tool.CreateTestUserSchema.input_schema()

      assert Map.keys(schema["properties"]) == ["email", "name"]
      refute Map.has_key?(schema["properties"], "age")
      refute Map.has_key?(schema["properties"], "password_hash")
    end
  end
end
