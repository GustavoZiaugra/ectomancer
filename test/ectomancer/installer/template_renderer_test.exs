defmodule Ectomancer.Installer.TemplateRendererTest do
  use ExUnit.Case, async: true
  alias Ectomancer.Installer.TemplateRenderer

  describe "generate_mcp_module_content/3" do
    test "generates MCP module with expose annotations" do
      schemas = [
        %{
          module: MyApp.Accounts.User,
          table: "users",
          context: "Accounts",
          associations: [:posts],
          writable_fields: [:email, :name]
        }
      ]

      content = TemplateRenderer.generate_mcp_module_content(schemas, "test-mcp", "1.0.0")

      assert String.contains?(content, "defmodule MyApp.MCP")
      assert String.contains?(content, "use Ectomancer")
      assert String.contains?(content, "expose")
      assert String.contains?(content, "MyApp.Accounts.User")
    end

    test "generates multiple expose annotations" do
      schemas = [
        %{
          module: MyApp.Accounts.User,
          table: "users",
          context: "Accounts",
          associations: [],
          writable_fields: [:email]
        },
        %{
          module: MyApp.Blog.Post,
          table: "posts",
          context: "Blog",
          associations: [],
          writable_fields: [:title]
        }
      ]

      content = TemplateRenderer.generate_mcp_module_content(schemas, "test-mcp", "1.0.0")

      assert String.contains?(content, "MyApp.Accounts.User")
      assert String.contains?(content, "MyApp.Blog.Post")
      assert String.match?(content, ~r/expose.*MyApp\.Accounts\.User/)
      assert String.match?(content, ~r/expose.*MyApp\.Blog\.Post/)
    end

    test "includes oban section when enabled" do
      schemas = [
        %{
          module: MyApp.Accounts.User,
          table: "users",
          context: "Accounts",
          associations: [],
          writable_fields: []
        }
      ]

      content =
        TemplateRenderer.generate_mcp_module_content(schemas, "test-mcp", "1.0.0", false, true)

      assert String.contains?(content, "expose_oban_jobs")
    end

    test "excludes oban section when disabled" do
      schemas = [
        %{
          module: MyApp.Accounts.User,
          table: "users",
          context: "Accounts",
          associations: [],
          writable_fields: []
        }
      ]

      content =
        TemplateRenderer.generate_mcp_module_content(schemas, "test-mcp", "1.0.0", false, false)

      refute String.contains?(content, "expose_oban_jobs")
    end
  end

  describe "generate_config_entry/1" do
    test "generates config with default repo" do
      content = TemplateRenderer.generate_config_entry()
      assert String.contains?(content, "config :ectomancer")
      assert String.contains?(content, "repo: MyApp.Repo")
    end

    test "generates config with custom repo" do
      content = TemplateRenderer.generate_config_entry(repo: "MyApp.CustomRepo")
      assert String.contains?(content, "repo: MyApp.CustomRepo")
    end
  end

  describe "generate_router_entry/1" do
    test "generates router forward route" do
      content = TemplateRenderer.generate_router_entry()
      assert String.contains?(content, 'forward "/mcp", Ectomancer.Plug')
    end
  end
end
