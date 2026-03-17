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
end
