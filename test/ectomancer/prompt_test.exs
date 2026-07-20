# credo:disable-for-this-file Credo.Check.Design.AliasUsage
defmodule Ectomancer.PromptTest do
  use ExUnit.Case
  doctest Ectomancer.Prompt

  defmodule TestUser do
    use Ecto.Schema

    schema "test_users" do
      field(:name, :string)
      field(:email, :string)
      timestamps()
    end
  end

  defmodule PromptMCP do
    use Ectomancer, name: "prompt-test", version: "1.0.0"

    expose(
      Ectomancer.PromptTest.TestUser,
      actions: [:list, :get]
    )

    prompt :analyze_churn do
      description("Analyze user churn over a time period")
      argument(:days, :integer, required: true, description: "Days to look back")
      argument(:threshold, :float, default: 0.05, description: "Churn threshold")

      messages fn args ->
        [
          %{
            role: :user,
            content: %{
              type: :text,
              text: "Using the list_users and get_user tools, analyze churn over the last #{args["days"]} days with threshold #{args["threshold"]}."
            }
          }
        ]
      end
    end

    prompt :summarize_reports do
      description("Summarize recent reports")
      argument(:report_type, :string,
        required: true,
        description: "Type of report",
        enum: ["sales", "inventory", "employee"]
      )

      messages fn args ->
        report_type = Map.get(args, "report_type", "sales")

        [
          %{
            role: :system,
            content: %{
              type: :text,
              text: "You are a report analyst. Summarize the #{report_type} reports."
            }
          },
          %{
            role: :user,
            content: %{
              type: :text,
              text: "Provide a concise summary of the latest #{report_type} reports."
            }
          }
        ]
      end
    end

    prompt :simple_prompt do
      description("A simple prompt without arguments")

      messages fn _args ->
        [
          %{
            role: :user,
            content: %{
              type: :text,
              text: "What is the weather today?"
            }
          }
        ]
      end
    end

    prompt :prompt_with_actor do
      description("Prompt that uses the actor")
      argument(:topic, :string, required: true, description: "Topic to analyze")

      messages fn args ->
        [
          %{
            role: :assistant,
            content: %{
              type: :text,
              text: "Please analyze the topic: #{args["topic"]}"
            }
          }
        ]
      end
    end

  end

  defmodule PromptMCP.Prompt.CrasherPrompt do
    def name, do: "crasher_prompt"
    def description, do: "A prompt that crashes"
    def __mcp_component_type__, do: :prompt
    def __scopes__, do: []

    def arguments, do: []

    def get_messages(_args, frame) do
      try do
        raise "Intentional crash for testing"
      rescue
        e ->
          error = %Anubis.MCP.Error{
            code: -32_603,
            message: "Prompt execution error: #{Exception.message(e)}",
            data: %{
              error: inspect(e),
              stacktrace: Exception.format_stacktrace(__STACKTRACE__)
            }
          }

          {:error, error, frame}
      end
    end
  end

  describe "prompt definition" do
    test "generates prompt module" do
      assert {:module, _} = Code.ensure_loaded(PromptMCP.Prompt.AnalyzeChurn)
    end

    test "prompt module has correct name" do
      assert PromptMCP.Prompt.AnalyzeChurn.name() == "analyze_churn"
    end

    test "prompt module has correct component type" do
      assert PromptMCP.Prompt.AnalyzeChurn.__mcp_component_type__() == :prompt
    end

    test "prompt module has description" do
      assert PromptMCP.Prompt.AnalyzeChurn.description() == "Analyze user churn over a time period"
    end
  end

  describe "arguments" do
    test "required argument is marked as required" do
      args = PromptMCP.Prompt.AnalyzeChurn.arguments()

      days_arg = Enum.find(args, &(&1["name"] == "days"))
      assert days_arg["required"] == true
      assert days_arg["description"] == "Days to look back"
    end

    test "optional argument with default is not required" do
      args = PromptMCP.Prompt.AnalyzeChurn.arguments()

      threshold_arg = Enum.find(args, &(&1["name"] == "threshold"))
      assert threshold_arg["required"] == false
      assert threshold_arg["default"] == 0.05
    end

    test "argument with enum values includes enum list" do
      args = PromptMCP.Prompt.SummarizeReports.arguments()

      type_arg = Enum.find(args, &(&1["name"] == "report_type"))
      assert type_arg["enum"] == ["sales", "inventory", "employee"]
    end

    test "simple prompt has no arguments" do
      args = PromptMCP.Prompt.SimplePrompt.arguments()
      assert args == []
    end
  end

  describe "get_messages execution" do
    test "returns messages with required argument" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      {:reply, response, _frame} =
        PromptMCP.Prompt.AnalyzeChurn.get_messages(%{"days" => "30", "threshold" => 0.1}, frame)

      assert response.type == :prompt
      assert length(response.messages) == 1

      assert [%{"role" => "user", "content" => %{"type" => "text", "text" => text}}] =
               response.messages

      assert text =~ "30"
      assert text =~ "0.1"
    end

    test "applies default value when not provided" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      {:reply, response, _frame} =
        PromptMCP.Prompt.AnalyzeChurn.get_messages(%{"days" => "7"}, frame)

      assert response.type == :prompt
      assert [%{"role" => "user", "content" => %{"type" => "text", "text" => text}}] =
               response.messages

      assert text =~ "7"
      assert text =~ "0.05"
    end

    test "simple prompt with no arguments returns single message" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      {:reply, response, _frame} = PromptMCP.Prompt.SimplePrompt.get_messages(%{}, frame)

      assert response.type == :prompt
      assert length(response.messages) == 1
      assert [%{"role" => "user", "content" => %{"type" => "text", "text" => "What is the weather today?"}}] =
               response.messages
    end

    test "prompt with multiple messages returns all of them" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      {:reply, response, _frame} =
        PromptMCP.Prompt.SummarizeReports.get_messages(%{"report_type" => "sales"}, frame)

      assert response.type == :prompt
      assert length(response.messages) == 2

      assert [%{"role" => "system", "content" => %{"type" => "text", "text" => text1}},
              %{"role" => "user", "content" => %{"type" => "text", "text" => text2}}] =
               response.messages

      assert text1 =~ "sales"
      assert text2 =~ "sales"
    end

    test "prompt uses assistant role" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      {:reply, response, _frame} =
        PromptMCP.Prompt.PromptWithActor.get_messages(%{"topic" => "security"}, frame)

      assert [%{"role" => "assistant", "content" => %{"type" => "text", "text" => text}}] =
               response.messages

      assert text =~ "security"
    end

    test "handles nil args gracefully" do
      frame = %Anubis.Server.Frame{assigns: %{}}
      {:reply, response, _frame} = PromptMCP.Prompt.SimplePrompt.get_messages(nil, frame)
      assert response.type == :prompt
    end
  end

  describe "prompt error handling" do
    test "handles exceptions in messages callback" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      result = PromptMCP.Prompt.CrasherPrompt.get_messages(%{}, frame)

      case result do
        {:error, %Anubis.MCP.Error{code: -32_603, message: msg}, _frame} ->
          assert msg =~ "Intentional crash for testing"

        _ ->
          flunk("Expected an error but got: #{inspect(result)}")
      end
    end
  end

  describe "prompt registration with MCP server" do
    test "prompts are registered as components" do
      components = PromptMCP.__components__(:prompt)
      prompt_names = Enum.map(components, & &1.name)

      assert "analyze_churn" in prompt_names
      assert "summarize_reports" in prompt_names
      assert "simple_prompt" in prompt_names
      assert "prompt_with_actor" in prompt_names
    end

    test "prompts coexist with exposed schemas" do
      assert {:module, _} = Code.ensure_loaded(PromptMCP.Prompt.AnalyzeChurn)
      assert {:module, _} = Code.ensure_loaded(PromptMCP.Resource.TestUser)
      assert {:module, _} = Code.ensure_loaded(PromptMCP.Resource.Schemas)
    end
  end

  describe "capabilities" do
    test "server includes prompts capability" do
      caps = PromptMCP.server_capabilities()
      assert Map.has_key?(caps, "prompts")
    end
  end
end
