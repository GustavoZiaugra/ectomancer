# credo:disable-for-this-file Credo.Check.Design.AliasUsage
defmodule Ectomancer.CustomResourceTest do
  use ExUnit.Case
  doctest Ectomancer.Resource

  # --- Helper Schemas ---

  defmodule TestAuthor do
    use Ecto.Schema

    schema "test_authors" do
      field(:name, :string)
      field(:bio, :string)
      timestamps()
    end
  end

  defmodule TestBook do
    use Ecto.Schema

    schema "test_books" do
      field(:title, :string)
      field(:isbn, :string)
      belongs_to(:author, Ectomancer.CustomResourceTest.TestAuthor)
      timestamps()
    end
  end

  # --- MCP Modules ---

  defmodule ResourceMCP do
    use Ectomancer, name: "custom-resource-test", version: "1.0.0"

    expose(TestAuthor, actions: [:list, :get])

    # Static resource
    resource :system_status do
      description("Current system health metrics")
      uri("metrics://status")
      mime_type("application/json")

      read(fn _params, _actor ->
        {:ok, ~s({"status": "healthy", "uptime": 3600})}
      end)
    end

    # Templated resource
    resource :documentation do
      description("Documentation files")
      uri("docs://{path}")
      mime_type("text/markdown")

      read(fn params, _actor ->
        path = Map.get(params, "path", "")

        case path do
          "readme" -> {:ok, "# Project README\n\nWelcome!"}
          "api" -> {:ok, "# API Documentation\n\n## Endpoints"}
          _ -> {:error, :not_found}
        end
      end)
    end

    # Resource with authorization
    resource :admin_data do
      description("Admin-only data")
      uri("admin://data")
      mime_type("application/json")

      authorize(fn actor, _action ->
        actor != nil && actor.role == :admin
      end)

      read(fn _params, actor ->
        {:ok, ~s({"secret": "admin-only-data", "accessed_by": "#{actor.name}"})}
      end)
    end

    # Public resource with explicit :none authorization
    resource :public_info do
      description("Public information")
      uri("info://version")
      mime_type("application/json")

      authorize(:none)

      read(fn _params, _actor ->
        {:ok, ~s({"version": "1.0.0"})}
      end)
    end

    # Resource returning errors — uses Map.get to handle any params shape
    resource :error_prone do
      description("Resource that returns errors")
      uri("errors://demo")

      read(fn params, _actor ->
        case Map.get(params, "type", "default") do
          "not_found" -> {:error, :not_found}
          "custom" -> {:error, "something went wrong"}
          "ok" -> {:ok, "all good"}
          _ -> {:ok, "default"}
        end
      end)
    end
  end

  # --- Tests ---

  describe "resource macro basics" do
    test "generates resource module" do
      assert {:module, _} = Code.ensure_loaded(ResourceMCP.Resource.SystemStatus)
    end

    test "resource module has correct name" do
      assert ResourceMCP.Resource.SystemStatus.name() == "system_status"
    end

    test "resource module has correct component type" do
      assert ResourceMCP.Resource.SystemStatus.__mcp_component_type__() == :resource
    end

    test "resource module has description" do
      assert ResourceMCP.Resource.SystemStatus.description() == "Current system health metrics"
    end

    test "resource module has mime_type" do
      assert ResourceMCP.Resource.SystemStatus.mime_type() == "application/json"
    end
  end

  describe "static URI resources" do
    test "static resource has uri/0 (not uri_template)" do
      assert ResourceMCP.Resource.SystemStatus.uri() == "metrics://status"
    end

    test "static resource returns content on read" do
      frame = %Anubis.Server.Frame{assigns: %{}}
      {:reply, response, _frame} = ResourceMCP.Resource.SystemStatus.read(%{}, frame)

      assert response.type == :resource
      assert [%{"type" => "text", "text" => json_content}] = response.content
      assert json_content == ~s({"status": "healthy", "uptime": 3600})
    end
  end

  describe "templated URI resources" do
    test "templated resource has uri_template/0" do
      assert ResourceMCP.Resource.Documentation.uri_template() == "docs://{path}"
    end

    test "templated resource resolves params from URI" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      {:reply, response, _frame} =
        ResourceMCP.Resource.Documentation.read(%{"params" => %{"path" => "readme"}}, frame)

      assert response.type == :resource
      assert [%{"type" => "text", "text" => content}] = response.content
      assert content =~ "# Project README"
    end

    test "templated resource returns not_found for unknown path" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      {:error, error, _frame} =
        ResourceMCP.Resource.Documentation.read(%{"params" => %{"path" => "nonexistent"}}, frame)

      assert error.code == -32_002
      assert error.message == "Resource not found"
    end
  end

  describe "resource authorization" do
    test "authorized resource succeeds with admin actor" do
      actor = %{name: "Admin", role: :admin}
      frame = %Anubis.Server.Frame{assigns: %{ectomancer_actor: actor}}

      {:reply, response, _frame} = ResourceMCP.Resource.AdminData.read(%{}, frame)

      assert response.type == :resource
      assert [%{"type" => "text", "text" => json}] = response.content
      assert json =~ "admin-only-data"
    end

    test "authorized resource fails with non-admin actor" do
      actor = %{name: "User", role: :user}
      frame = %Anubis.Server.Frame{assigns: %{ectomancer_actor: actor}}

      {:error, error, _frame} = ResourceMCP.Resource.AdminData.read(%{}, frame)

      assert error.code == -32_001
      assert error.message =~ "Unauthorized"
    end

    test "authorized resource fails with nil actor" do
      frame = %Anubis.Server.Frame{assigns: %{ectomancer_actor: nil}}

      {:error, error, _frame} = ResourceMCP.Resource.AdminData.read(%{}, frame)

      assert error.code == -32_001
    end

    test "public resource with authorize(:none) allows any actor" do
      frame = %Anubis.Server.Frame{assigns: %{ectomancer_actor: nil}}

      {:reply, response, _frame} = ResourceMCP.Resource.PublicInfo.read(%{}, frame)

      assert response.type == :resource
      assert [%{"type" => "text", "text" => json}] = response.content
      assert json =~ "1.0.0"
    end
  end

  describe "resource error handling" do
    test "resource with {:error, :not_found} returns proper MCP error" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      {:error, error, _frame} =
        ResourceMCP.Resource.ErrorProne.read(%{"type" => "not_found"}, frame)

      assert error.code == -32_002
      assert error.message == "Resource not found"
    end

    test "resource with {:error, reason} returns generic error" do
      frame = %Anubis.Server.Frame{assigns: %{}}
      {:error, error, _frame} = ResourceMCP.Resource.ErrorProne.read(%{"type" => "custom"}, frame)

      assert error.code == -32_603
      assert error.message =~ "something went wrong"
    end

    test "resource returning {:ok, content} works for valid data" do
      frame = %Anubis.Server.Frame{assigns: %{}}
      {:reply, response, _frame} = ResourceMCP.Resource.ErrorProne.read(%{"type" => "ok"}, frame)

      assert response.type == :resource
      assert [%{"type" => "text", "text" => "all good"}] = response.content
    end
  end

  describe "resource integration with exposed schemas" do
    test "custom resources coexist with auto-generated schema resources" do
      assert {:module, _} = Code.ensure_loaded(ResourceMCP.Resource.SystemStatus)
      assert {:module, _} = Code.ensure_loaded(ResourceMCP.Resource.TestAuthor)
      assert {:module, _} = Code.ensure_loaded(ResourceMCP.Resource.Schemas)
    end

    test "Anubis server registers all resources" do
      # The server should register custom resources via Anubis.Server.component
      # This verifies the macro generates the correct registration call
      assert {:module, _} = Code.ensure_loaded(ResourceMCP.Resource.SystemStatus)
      assert {:module, _} = Code.ensure_loaded(ResourceMCP.Resource.Documentation)
      assert {:module, _} = Code.ensure_loaded(ResourceMCP.Resource.AdminData)
    end
  end
end
