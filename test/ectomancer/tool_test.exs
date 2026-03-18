defmodule Ectomancer.ToolTest do
  use ExUnit.Case

  alias __MODULE__.TestMCP, as: TestMCP
  alias TestMCP.Tool.Add
  alias TestMCP.Tool.GreetOptional
  alias TestMCP.Tool.Hello

  defmodule TestMCP do
    use Ectomancer,
      name: "test-mcp",
      version: "1.0.0"

    tool :hello do
      description("Say hello to someone")
      param(:name, :string, required: true)

      handle(fn %{"name" => name}, _actor ->
        {:ok, "Hello, #{name}!"}
      end)
    end

    tool :add do
      description("Add two numbers")
      param(:a, :integer, required: true)
      param(:b, :integer, required: true)

      handle(fn %{"a" => a, "b" => b}, _actor ->
        {:ok, a + b}
      end)
    end

    tool :greet_optional do
      description("Greet with optional name")
      param(:name, :string, required: false)

      handle(fn params, _actor ->
        name = params["name"] || "World"
        {:ok, "Hello, #{name}!"}
      end)
    end
  end

  describe "tool definition" do
    test "defines tool module" do
      assert Code.ensure_loaded?(Hello)
    end

    test "tool has correct name" do
      assert Hello.name() == "hello"
    end

    test "tool has description" do
      assert Hello.__description__() == "Say hello to someone"
    end

    test "tool has JSON Schema input format" do
      schema = Hello.input_schema()

      # JSON Schema format for external communication
      assert schema["type"] == "object"
      assert schema["properties"]["name"]["type"] == "string"
      assert "name" in schema["required"]
    end

    test "tool with multiple params has correct JSON Schema" do
      schema = Add.input_schema()

      assert schema["properties"]["a"]["type"] == "integer"
      assert schema["properties"]["b"]["type"] == "integer"
      assert "a" in schema["required"]
      assert "b" in schema["required"]
    end

    test "optional params are not in required list" do
      schema = GreetOptional.input_schema()

      assert schema["properties"]["name"]["type"] == "string"
      required = schema["required"] || []
      refute "name" in required
    end
  end

  describe "tool execution" do
    test "executes tool handler successfully" do
      frame = %{assigns: %{ectomancer_actor: nil}}
      result = Hello.execute(%{"name" => "Alice"}, frame)

      assert {:reply, %Anubis.Server.Response{content: [%{"text" => text}]}, _} = result
      assert text =~ "Hello, Alice!"
    end

    test "executes tool with actor" do
      actor = %{id: 1, name: "Admin"}
      frame = %{assigns: %{ectomancer_actor: actor}}

      # The handler receives the actor as second argument
      # (we're testing that frame.assigns is accessible)
      result = Hello.execute(%{"name" => "Bob"}, frame)
      assert {:reply, %Anubis.Server.Response{content: [%{"text" => text}]}, _} = result
      assert text =~ "Hello, Bob!"
    end

    test "executes tool with multiple params" do
      frame = %{assigns: %{}}
      result = Add.execute(%{"a" => 3, "b" => 5}, frame)

      assert {:reply, %Anubis.Server.Response{content: [%{"text" => text}]}, _} = result
      assert text =~ "8"
    end

    test "handles optional params" do
      frame = %{assigns: %{}}

      # Without optional param
      result = GreetOptional.execute(%{}, frame)
      assert {:reply, %Anubis.Server.Response{content: [%{"text" => text}]}, _} = result
      assert text =~ "Hello, World!"

      # With optional param
      result = GreetOptional.execute(%{"name" => "Charlie"}, frame)
      assert {:reply, %Anubis.Server.Response{content: [%{"text" => text}]}, _} = result
      assert text =~ "Hello, Charlie!"
    end
  end

  describe "component registration" do
    test "tools are registered as components" do
      components = TestMCP.__components__(:tool)
      tool_names = Enum.map(components, & &1.name)

      assert "hello" in tool_names
      assert "add" in tool_names
      assert "greet_optional" in tool_names
    end
  end

  describe "changeset error mapping" do
    test "format_error maps changeset errors properly" do
      changeset = %Ecto.Changeset{
        errors: [email: {"can't be blank", []}, name: {"has invalid format", []}],
        valid?: false
      }

      {code, message, data} = Ectomancer.Tool.format_error(changeset)

      assert code == -32_602
      assert message == "Missing required field(s)"
      assert data[:count] == 2
      assert is_list(data[:errors])
    end

    test "map_changeset_errors formats errors into readable messages" do
      changeset = %Ecto.Changeset{
        errors: [
          email: {"can't be blank", []},
          age: {"must be at least %{count}", [count: 18]}
        ],
        valid?: false
      }

      errors = Ectomancer.Tool.map_changeset_errors(changeset)

      assert errors.email == ["can't be blank"]
      assert errors.age == ["must be at least 18"]
    end

    test "format_field_name converts snake_case to Title Case" do
      assert Ectomancer.Tool.format_field_name(:email) == "Email"
      assert Ectomancer.Tool.format_field_name(:first_name) == "First name"
      assert Ectomancer.Tool.format_field_name("last_name") == "Last name"
    end

    test "infer_validation_type detects presence errors" do
      errors = %{email: ["can't be blank"]}
      assert Ectomancer.Tool.infer_validation_type(errors) == :presence
    end

    test "infer_validation_type detects format errors" do
      errors = %{email: ["has invalid format"]}
      assert Ectomancer.Tool.infer_validation_type(errors) == :format
    end

    test "infer_validation_type detects inclusion errors" do
      errors = %{status: ["is invalid"]}
      assert Ectomancer.Tool.infer_validation_type(errors) == :inclusion
    end

    test "infer_validation_type detects length errors" do
      errors = %{password: ["string too short"]}
      assert Ectomancer.Tool.infer_validation_type(errors) == :length
    end

    test "infer_validation_type detects comparison errors" do
      errors = %{age: ["must be greater than 0"]}
      assert Ectomancer.Tool.infer_validation_type(errors) == :comparison
    end

    test "infer_validation_type defaults to other for unknown errors" do
      errors = %{field: ["some random error"]}
      assert Ectomancer.Tool.infer_validation_type(errors) == :other
    end

    test "changeset errors include field names in structured format" do
      changeset = %Ecto.Changeset{
        errors: [email_address: {"can't be blank", []}],
        valid?: false
      }

      {_, _, data} = Ectomancer.Tool.format_error(changeset)

      [first_error | _] = data[:errors]
      assert first_error[:field] == "Email address"
      assert first_error[:message] == "can't be blank"
    end

    test "flatten_errors combines multiple messages into single string" do
      errors = %{email: ["can't be blank", "is invalid"], name: ["is too short"]}
      flattened = Ectomancer.Tool.flatten_errors(errors)

      assert flattened.email == "can't be blank, is invalid"
      assert flattened.name == "is too short"
    end
  end
end
