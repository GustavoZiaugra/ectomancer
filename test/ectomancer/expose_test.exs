defmodule Ectomancer.ExposeTest do
  use ExUnit.Case

  alias Ectomancer.ExposeTest.TestMCP.Tool.CreateTestUserSchema
  alias Ectomancer.ExposeTest.TestMCP.Tool.GetTestUserSchema
  alias Ectomancer.ExposeTest.TestMCP.Tool.ListTestUserSchemas

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

  describe "expose/2 macro" do
    test "generates list_test_user_schemas tool" do
      assert Code.ensure_loaded?(ListTestUserSchemas)
    end

    test "generates get_test_user_schema tool" do
      assert Code.ensure_loaded?(GetTestUserSchema)
    end

    test "generates create_test_user_schema tool" do
      assert Code.ensure_loaded?(CreateTestUserSchema)
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
      assert ListTestUserSchemas.name() == "list_test_user_schemas"
    end

    test "has JSON Schema format" do
      schema = ListTestUserSchemas.input_schema()
      # JSON Schema format for external communication
      assert schema["type"] == "object"
      assert is_map(schema["properties"])
    end

    test "is registered as a component" do
      tools = TestMCP.__components__(:tool)
      tool_names = Enum.map(tools, & &1.name)
      assert "list_test_user_schemas" in tool_names
    end
  end

  describe "get_test_user_schema tool" do
    test "has correct name" do
      assert GetTestUserSchema.name() == "get_test_user_schema"
    end

    test "has JSON Schema with required id param" do
      schema = GetTestUserSchema.input_schema()
      # JSON Schema format
      assert schema["type"] == "object"
      assert schema["properties"]["id"]["type"] == "integer"
      assert "id" in schema["required"]
    end
  end

  describe "create_test_user_schema tool" do
    test "has correct name" do
      assert CreateTestUserSchema.name() == "create_test_user_schema"
    end

    test "has JSON Schema format" do
      schema = CreateTestUserSchema.input_schema()
      # JSON Schema format
      assert schema["type"] == "object"
      assert is_map(schema["properties"])
      # Should NOT have id, timestamps
      refute schema["properties"]["id"]
    end
  end

  describe "tool modules are generated" do
    test "all expected tool modules exist" do
      assert Code.ensure_loaded?(ListTestUserSchemas)
      assert Code.ensure_loaded?(GetTestUserSchema)
      assert Code.ensure_loaded?(CreateTestUserSchema)
    end

    test "tools have execute function" do
      assert function_exported?(ListTestUserSchemas, :execute, 2)
      assert function_exported?(GetTestUserSchema, :execute, 2)
      assert function_exported?(CreateTestUserSchema, :execute, 2)
    end
  end

  describe "readonly mode" do
    defmodule ReadonlyTestMCP do
      use Ectomancer, name: "readonly-test-mcp", version: "1.0.0"

      expose(TestUserSchema, readonly: true)
    end

    alias ReadonlyTestMCP.Tool.GetTestUserSchema, as: ReadonlyGet
    alias ReadonlyTestMCP.Tool.ListTestUserSchemas, as: ReadonlyList

    test "generates list_test_user_schemas tool" do
      assert Code.ensure_loaded?(ReadonlyList)
    end

    test "generates get_test_user_schema tool" do
      assert Code.ensure_loaded?(ReadonlyGet)
    end

    test "does not generate create tool in readonly mode" do
      refute Code.ensure_loaded?(ReadonlyTestMCP.Tool.CreateTestUserSchema)
    end

    test "does not generate update tool in readonly mode" do
      refute Code.ensure_loaded?(ReadonlyTestMCP.Tool.UpdateTestUserSchema)
    end

    test "does not generate destroy tool in readonly mode" do
      refute Code.ensure_loaded?(ReadonlyTestMCP.Tool.DestroyTestUserSchema)
    end

    test "readonly mode generates exactly 2 tools" do
      tools = ReadonlyTestMCP.__components__(:tool)
      assert length(tools) == 2

      tool_names = Enum.map(tools, & &1.name)
      assert "list_test_user_schemas" in tool_names
      assert "get_test_user_schema" in tool_names
    end
  end
end
