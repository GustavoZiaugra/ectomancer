defmodule Ectomancer.AnubisInputValidationTest do
  use ExUnit.Case

  alias Anubis.Server.{Frame, Response}

  defmodule TestMCP do
    use Ectomancer, name: "validation-test", version: "1.0.0"

    tool :echo do
      description("Echo back the message")
      param(:message, :string, required: true)
      param(:times, :integer)

      handle(fn %{"message" => msg}, _actor ->
        {:ok, %{message: msg}}
      end)
    end

    prompt :greet do
      description("Greet someone")

      argument(:name, :string, required: true)

      messages(fn args ->
        [
          %{
            role: "user",
            content: %{type: "text", text: "Hi #{args["name"]}"}
          }
        ]
      end)
    end
  end

  # Anubis >= 2.1 builds a component's input validator from `mcp_schema/1`.
  # Without it, `validate_input` is nil and every `tools/call` / prompts/get
  # argument is dropped before the handler runs.
  describe "anubis input validators" do
    test "tool components expose a working validate_input" do
      tool = Enum.find(TestMCP.__components__(:tool), &(&1.name == "echo"))

      assert tool, "echo tool component not found"
      refute is_nil(tool.validate_input), "anubis would drop all tool arguments"

      assert {:ok, %{message: "hi", times: 2}} =
               tool.validate_input.(%{"message" => "hi", "times" => 2})

      assert {:error, _errors} = tool.validate_input.(%{})
    end

    test "prompt components expose a working validate_input" do
      prompt = Enum.find(TestMCP.__components__(:prompt), &(&1.name == "greet"))

      assert prompt, "greet prompt component not found"
      refute is_nil(prompt.validate_input), "anubis would drop all prompt arguments"

      assert {:ok, %{"name" => "Ada"}} = prompt.validate_input.(%{"name" => "Ada"})
      assert {:error, _errors} = prompt.validate_input.(%{})
    end

    test "tool handlers receive the validated client arguments" do
      tool = Enum.find(TestMCP.__components__(:tool), &(&1.name == "echo"))
      {:ok, params} = tool.validate_input.(%{"message" => "hello"})

      frame = Frame.new(%{ectomancer_actor: nil})

      assert {:reply, %Response{content: [content]}, _frame} =
               tool.handler.execute(params, frame)

      assert %{"type" => "text", "text" => text} = content
      assert text =~ "hello"
    end

    test "custom tool modules export mcp_schema/1" do
      tool_module = Module.concat(TestMCP, "Tool.Echo")

      assert function_exported?(tool_module, :mcp_schema, 1)

      assert {:ok, %{message: "hi"}} = tool_module.mcp_schema(%{"message" => "hi"})
      assert {:error, _errors} = tool_module.mcp_schema(%{})
    end
  end
end
