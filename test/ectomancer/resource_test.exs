# credo:disable-for-this-file Credo.Check.Design.AliasUsage
defmodule Ectomancer.ResourceTest do
  use ExUnit.Case

  defmodule TestUser do
    use Ecto.Schema

    schema "test_users" do
      field(:email, :string)
      field(:name, :string)
      field(:age, :integer)
      timestamps()
    end
  end

  defmodule TestPost do
    use Ecto.Schema

    schema "test_posts" do
      field(:title, :string)
      field(:body, :string)
      belongs_to(:user, Ectomancer.ResourceTest.TestUser)
      timestamps()
    end
  end

  defmodule ResourceMCP do
    use Ectomancer, name: "resource-test", version: "1.0.0"

    expose(TestUser, actions: [:list, :get, :create])
    expose(TestPost, actions: [:list, :get])
  end

  describe "per-schema resource generation" do
    test "generates Resource module for each schema" do
      assert {:module, _} = Code.ensure_loaded(ResourceMCP.Resource.TestUser)
      assert {:module, _} = Code.ensure_loaded(ResourceMCP.Resource.TestPost)
    end

    test "resource module has correct URI" do
      assert ResourceMCP.Resource.TestUser.uri() == "ectomancer://schemas/test_user"
      assert ResourceMCP.Resource.TestPost.uri() == "ectomancer://schemas/test_post"
    end

    test "resource module has correct name" do
      assert ResourceMCP.Resource.TestUser.name() == "test_user"
      assert ResourceMCP.Resource.TestPost.name() == "test_post"
    end

    test "resource module has description" do
      assert ResourceMCP.Resource.TestUser.description() == "Schema metadata for test_user"
      assert ResourceMCP.Resource.TestPost.description() == "Schema metadata for test_post"
    end

    test "resource read returns JSON with schema metadata" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      {:reply, response, _frame} = ResourceMCP.Resource.TestUser.read(%{}, frame)

      assert response.type == :resource
      assert [%{"type" => "text", "text" => json}] = response.content

      metadata = Jason.decode!(json)

      assert metadata["name"] == "test_user"
      assert metadata["module"] == "Ectomancer.ResourceTest.TestUser"
      assert metadata["uri"] == "ectomancer://schemas/test_user"
      assert is_list(metadata["fields"])
      assert is_list(metadata["associations"])
      assert is_list(metadata["primary_key"])
      assert is_list(metadata["available_actions"])
    end

    test "resource fields contain type and required info" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      {:reply, response, _frame} = ResourceMCP.Resource.TestPost.read(%{}, frame)

      assert [%{"text" => json}] = response.content
      metadata = Jason.decode!(json)

      title_field = Enum.find(metadata["fields"], fn f -> f["name"] == "title" end)
      assert title_field
      assert title_field["type"] == "string"
    end

    test "resource available_actions reflects expose config" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      {:reply, response, _frame} = ResourceMCP.Resource.TestUser.read(%{}, frame)
      assert [%{"text" => json}] = response.content
      metadata = Jason.decode!(json)

      # TestUser has list, get, create (not update or destroy)
      assert "list" in metadata["available_actions"]
      assert "get" in metadata["available_actions"]
      assert "create" in metadata["available_actions"]
      refute "update" in metadata["available_actions"]
      refute "destroy" in metadata["available_actions"]
    end

    test "resource associations reflect schema relationships" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      {:reply, response, _frame} = ResourceMCP.Resource.TestPost.read(%{}, frame)
      assert [%{"text" => json}] = response.content
      metadata = Jason.decode!(json)

      user_assoc = Enum.find(metadata["associations"], fn a -> a["name"] == "user" end)
      assert user_assoc
      assert user_assoc["type"] == "one"
      assert user_assoc["related"] == "Ectomancer.ResourceTest.TestUser"
    end
  end

  describe "top-level schemas resource" do
    test "generates Resource.Schemas module" do
      assert {:module, _} = Code.ensure_loaded(ResourceMCP.Resource.Schemas)
    end

    test "has correct URI" do
      assert ResourceMCP.Resource.Schemas.uri() == "ectomancer://schemas"
    end

    test "lists all registered schemas" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      {:reply, response, _frame} = ResourceMCP.Resource.Schemas.read(%{}, frame)

      assert [%{"type" => "text", "text" => json}] = response.content
      result = Jason.decode!(json)

      assert is_map(result)
      assert is_list(result["schemas"])

      schema_names = Enum.map(result["schemas"], fn s -> s["name"] end)
      assert "test_user" in schema_names
      assert "test_post" in schema_names
    end

    test "schemas listing includes URI and title" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      {:reply, response, _frame} = ResourceMCP.Resource.Schemas.read(%{}, frame)
      assert [%{"text" => json}] = response.content
      result = Jason.decode!(json)

      test_user_entry = Enum.find(result["schemas"], fn s -> s["name"] == "test_user" end)
      assert test_user_entry
      assert test_user_entry["uri"] == "ectomancer://schemas/test_user"
      assert test_user_entry["title"] == "TestUser Schema"
    end
  end

  describe "resource opt-out with resource: false" do
    defmodule OtherSchema do
      use Ecto.Schema

      schema "other_records" do
        field(:label, :string)
        timestamps()
      end
    end

    defmodule NoResourceMCP do
      use Ectomancer, name: "no-resource-test", version: "1.0.0"

      expose(TestUser, resource: false, actions: [:list])
      expose(OtherSchema, actions: [:list])
    end

    test "does not generate Resource module for opt-out schemas" do
      refute Code.ensure_loaded?(NoResourceMCP.Resource.TestUser)
    end

    test "still generates tools even without resource" do
      assert Code.ensure_loaded?(NoResourceMCP.Tool.ListTestUsers)
    end

    test "excluded schema does not appear in top-level schemas" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      {:reply, response, _frame} = NoResourceMCP.Resource.Schemas.read(%{}, frame)
      assert [%{"text" => json}] = response.content
      result = Jason.decode!(json)

      schema_names = Enum.map(result["schemas"], fn s -> s["name"] end)
      refute "test_user" in schema_names
      assert "other_schema" in schema_names
    end
  end

  describe "resource with namespace" do
    defmodule NamespacedResourceMCP do
      use Ectomancer, name: "namespace-test", version: "1.0.0"

      expose(TestUser, namespace: :admin, actions: [:list])
    end

    test "uri includes namespace prefix" do
      assert NamespacedResourceMCP.Resource.AdminTestUser.uri() ==
               "ectomancer://schemas/admin_test_user"
    end

    test "top-level schemas include namespaced resources" do
      frame = %Anubis.Server.Frame{assigns: %{}}

      {:reply, response, _frame} = NamespacedResourceMCP.Resource.Schemas.read(%{}, frame)
      assert [%{"text" => json}] = response.content
      result = Jason.decode!(json)

      schema_names = Enum.map(result["schemas"], fn s -> s["name"] end)
      assert "test_user" in schema_names
    end
  end

  describe "resource with custom name via :as" do
    defmodule AliasedResourceMCP do
      use Ectomancer, name: "alias-test", version: "1.0.0"

      expose(TestUser, as: :admin_users, actions: [:list])
    end

    test "uri uses the custom name" do
      assert AliasedResourceMCP.Resource.AdminUsers.uri() ==
               "ectomancer://schemas/admin_users"
    end

    test "resource name is the aliased name" do
      assert AliasedResourceMCP.Resource.AdminUsers.name() == "admin_users"
    end
  end

  describe "parse_authorize_handler/1" do
    alias Ectomancer.Resource

    test ":none returns nil" do
      assert Resource.parse_authorize_handler(:none) == nil
    end

    test "[with: module] returns module" do
      assert Resource.parse_authorize_handler(with: TestUser) == TestUser
    end

    test "{:with, _, [module]} returns module" do
      assert Resource.parse_authorize_handler({:with, [], [TestUser]}) == TestUser
    end

    test "fn AST is returned as-is" do
      fn_ast = {:fn, [], []}
      assert Resource.parse_authorize_handler(fn_ast) == fn_ast
    end

    test "capture AST is returned as-is" do
      cap_ast = {:&, [], []}
      assert Resource.parse_authorize_handler(cap_ast) == cap_ast
    end

    test "anonymous function is returned as-is" do
      fun = fn _, _ -> true end
      assert Resource.parse_authorize_handler(fun) == fun
    end

    test "invalid handler raises" do
      handler = String.to_atom("invalid")

      assert_raise ArgumentError, ~r/Invalid authorization handler/, fn ->
        Resource.parse_authorize_handler(handler)
      end
    end
  end

  describe "flatten_block_items/1" do
    alias Ectomancer.Resource

    test "flattens nested __block__ items" do
      items = [
        {:__block__, [],
         [{:uri, [], ["test://uri"]}, {:__block__, [], [{:description, [], ["desc"]}]}]}
      ]

      result = Resource.flatten_block_items(items)

      assert length(result) == 2
    end

    test "passes through non-block items" do
      items = [{:uri, [], ["test://uri"]}, {:description, [], ["desc"]}]
      result = Resource.flatten_block_items(items)

      assert length(result) == 2
    end
  end
end
