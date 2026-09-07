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

    expose(TestUserSchema, actions: [:list, :get, :create], authorize: :none)
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

  describe "advanced options" do
    test "preloadable: false generates valid tools" do
      defmodule PreloadFalseMCP do
        use Ectomancer, name: "pf-mcp", version: "1.0.0"
        expose(TestUserSchema, actions: [:list], preloadable: false)
      end

      assert Code.ensure_loaded?(PreloadFalseMCP.Tool.ListTestUserSchemas)
    end

    test "preloadable with explicit list generates valid tools" do
      defmodule PreloadListMCP do
        use Ectomancer, name: "pl-mcp", version: "1.0.0"
        expose(TestUserSchema, actions: [:list], preloadable: [:posts])
      end

      assert Code.ensure_loaded?(PreloadListMCP.Tool.ListTestUserSchemas)
    end

    test "soft_delete: false generates valid tools" do
      defmodule SoftDeleteFalseMCP do
        use Ectomancer, name: "sdf-mcp", version: "1.0.0"
        expose(TestUserSchema, actions: [:list], soft_delete: false)
      end

      assert Code.ensure_loaded?(SoftDeleteFalseMCP.Tool.ListTestUserSchemas)
    end

    test "soft_delete with custom field generates valid tools" do
      defmodule SoftDeleteFieldMCP do
        use Ectomancer, name: "sdfield-mcp", version: "1.0.0"
        expose(TestUserSchema, actions: [:list], soft_delete: :deleted_at, authorize: :none)
      end

      assert Code.ensure_loaded?(SoftDeleteFieldMCP.Tool.ListTestUserSchemas)
    end

    test "expose with :as option generates aliased tools" do
      defmodule AsOptionMCP do
        use Ectomancer, name: "as-mcp", version: "1.0.0"
        expose(TestUserSchema, as: :admin_users, actions: [:list])
      end

      assert Code.ensure_loaded?(AsOptionMCP.Tool.ListAdminUsers)
    end

    test "expose with :except filters out fields" do
      defmodule ExceptMCP do
        use Ectomancer, name: "exc-mcp", version: "1.0.0"
        expose(TestUserSchema, actions: [:create], except: [:password_hash], authorize: :none)
      end

      assert Code.ensure_loaded?(ExceptMCP.Tool.CreateTestUserSchema)
    end
  end

  describe "upsert action" do
    defmodule UpsertMCP do
      use Ectomancer, name: "upsert-mcp", version: "1.0.0"

      expose(TestUserSchema,
        actions: [:upsert],
        conflict_target: :email,
        authorize: :none
      )
    end

    alias UpsertMCP.Tool.UpsertTestUserSchema

    test "generates upsert tool" do
      assert Code.ensure_loaded?(UpsertTestUserSchema)
    end

    test "has correct name" do
      assert UpsertTestUserSchema.name() == "upsert_test_user_schema"
    end

    test "has JSON Schema with writable fields" do
      schema = UpsertTestUserSchema.input_schema()
      assert schema["type"] == "object"
      assert schema["properties"]["email"]["type"] == "string"
      assert schema["properties"]["name"]["type"] == "string"
      assert schema["properties"]["age"]["type"] == "integer"
    end

    test "does not include primary key in params" do
      schema = UpsertTestUserSchema.input_schema()
      refute schema["properties"]["id"]
    end

    test "has execute function" do
      assert function_exported?(UpsertTestUserSchema, :execute, 2)
    end

    test "is registered as a component" do
      tools = UpsertMCP.__components__(:tool)
      tool_names = Enum.map(tools, & &1.name)
      assert "upsert_test_user_schema" in tool_names
    end
  end

  describe "upsert compile-time validation" do
    test "raises when conflict_target is missing with :upsert action" do
      assert_raise ArgumentError, ~r/conflict_target/, fn ->
        Code.eval_string("""
        defmodule NoConflictTargetMCP do
          use Ectomancer, name: "no-ct-mcp", version: "1.0.0"
          expose(Ectomancer.ExposeTest.TestUserSchema, actions: [:upsert])
        end
        """)
      end
    end

    test "raises with descriptive message when conflict_target is missing" do
      assert_raise ArgumentError, ~r/conflict_target/, fn ->
        Code.eval_string("""
        defmodule NoConflictTargetMsgMCP do
          use Ectomancer, name: "no-ct-msg-mcp", version: "1.0.0"
          expose(Ectomancer.ExposeTest.TestUserSchema, actions: [:list, :upsert])
        end
        """)
      end
    end
  end

  describe "default actions (fail-closed default)" do
    defmodule DefaultActionsMCP do
      use Ectomancer, name: "default-actions-mcp", version: "1.0.0"

      expose(TestUserSchema)
    end

    test "generates list and get tools by default" do
      assert Code.ensure_loaded?(DefaultActionsMCP.Tool.ListTestUserSchemas)
      assert Code.ensure_loaded?(DefaultActionsMCP.Tool.GetTestUserSchema)
    end

    test "does not generate mutating tools by default" do
      refute Code.ensure_loaded?(DefaultActionsMCP.Tool.CreateTestUserSchema)
      refute Code.ensure_loaded?(DefaultActionsMCP.Tool.UpdateTestUserSchema)
      refute Code.ensure_loaded?(DefaultActionsMCP.Tool.DestroyTestUserSchema)
      refute Code.ensure_loaded?(DefaultActionsMCP.Tool.BatchCreateTestUserSchemas)
    end
  end

  describe "fail-closed authorization for mutating actions" do
    test "raises at compile time when a mutating action has no authorization" do
      assert_raise ArgumentError, ~r/without effective authorization/, fn ->
        Code.eval_string("""
        defmodule NoAuthCreateMCP do
          use Ectomancer, name: "no-auth-create-mcp", version: "1.0.0"
          expose(Ectomancer.ExposeTest.TestUserSchema, actions: [:create])
        end
        """)
      end
    end

    test "raises at compile time for batch mutating actions without authorization" do
      assert_raise ArgumentError, ~r/without effective authorization/, fn ->
        Code.eval_string("""
        defmodule NoAuthBatchMCP do
          use Ectomancer, name: "no-auth-batch-mcp", version: "1.0.0"
          expose(Ectomancer.ExposeTest.TestUserSchema, actions: [:batch_destroy])
        end
        """)
      end
    end

    test "raises at compile time when soft_delete auto-adds restore without authorization" do
      assert_raise ArgumentError, ~r/without effective authorization/, fn ->
        Code.eval_string("""
        defmodule NoAuthRestoreMCP do
          use Ectomancer, name: "no-auth-restore-mcp", version: "1.0.0"
          expose(Ectomancer.ExposeTest.TestUserSchema, actions: [:list], soft_delete: :deleted_at)
        end
        """)
      end
    end

    test "explicit authorize: :none bypasses the fail-closed raise" do
      assert Code.eval_string("""
             defmodule ExplicitNoneCreateMCP do
               use Ectomancer, name: "explicit-none-create-mcp", version: "1.0.0"
               expose(Ectomancer.ExposeTest.TestUserSchema, actions: [:create], authorize: :none)
             end
             """)
    end

    test "real authorize option bypasses the fail-closed raise" do
      assert Code.eval_string("""
             defmodule AuthorizedCreateMCP do
               use Ectomancer, name: "auth-create-mcp", version: "1.0.0"
               expose(Ectomancer.ExposeTest.TestUserSchema,
                 actions: [:create],
                 authorize: fn actor, _action -> actor.role == :admin end
               )
             end
             """)
    end

    test "per-action authorize covering the mutating action bypasses the raise" do
      assert Code.eval_string("""
             defmodule PerActionCreateMCP do
               use Ectomancer, name: "per-action-create-mcp", version: "1.0.0"
               expose(Ectomancer.ExposeTest.TestUserSchema,
                 actions: [:list, :get, :create],
                 authorize: [
                   list: :public,
                   get: :public,
                   create: fn actor, _action -> actor.role == :admin end
                 ]
               )
             end
             """)
    end

    test "explicit per-action :none for the mutating action bypasses the raise" do
      assert Code.eval_string("""
             defmodule PerActionNoneCreateMCP do
               use Ectomancer, name: "per-action-none-create-mcp", version: "1.0.0"
               expose(Ectomancer.ExposeTest.TestUserSchema,
                 actions: [:list, :create],
                 authorize: [list: :none, create: :none]
               )
             end
             """)
    end

    test "read-only actions never trigger the raise" do
      assert Code.eval_string("""
             defmodule ReadOnlyNoAuthMCP do
               use Ectomancer, name: "ro-no-auth-mcp", version: "1.0.0"
               expose(Ectomancer.ExposeTest.TestUserSchema, actions: [:list, :get])
             end
             """)
    end

    test "readonly: true removes mutating actions and never triggers the raise" do
      assert Code.eval_string("""
             defmodule ReadonlyNoAuthMCP do
               use Ectomancer, name: "ro-no-auth-readonly-mcp", version: "1.0.0"
               expose(Ectomancer.ExposeTest.TestUserSchema,
                 actions: [:create, :update, :destroy],
                 readonly: true
               )
             end
             """)
    end

    test "global auth from use Ectomancer bypasses the raise" do
      assert Code.eval_string("""
             defmodule GlobalAuthCreateMCP do
               use Ectomancer,
                 name: "global-auth-create-mcp",
                 version: "1.0.0",
                 authorize: fn actor, _action -> actor.role == :admin end

               expose(Ectomancer.ExposeTest.TestUserSchema, actions: [:create])
             end
             """)
    end

    test "authorize: [all: :none] bypasses the fail-closed raise" do
      assert Code.eval_string("""
             defmodule AllNoneCreateMCP do
               use Ectomancer, name: "all-none-create-mcp", version: "1.0.0"
               expose(Ectomancer.ExposeTest.TestUserSchema,
                 actions: [:list, :create],
                 authorize: [all: :none]
               )
             end
             """)
    end

    test "authorize: [all: fn] bypasses the fail-closed raise" do
      assert Code.eval_string("""
             defmodule AllFnCreateMCP do
               use Ectomancer, name: "all-fn-create-mcp", version: "1.0.0"
               expose(Ectomancer.ExposeTest.TestUserSchema,
                 actions: [:create],
                 authorize: [all: fn actor, _action -> actor != nil end]
               )
             end
             """)
    end

    test "explicit authorize: nil does not bypass server-level global auth" do
      assert Code.eval_string("""
             defmodule NilAuthGlobalMCP do
               use Ectomancer,
                 name: "nil-auth-global-mcp",
                 version: "1.0.0",
                 authorize: fn actor, _action -> actor != nil end

               expose(Ectomancer.ExposeTest.TestUserSchema,
                 actions: [:create],
                 authorize: nil
               )
             end
             """)
    end

    test "readonly: true with soft_delete does not raise and excludes restore" do
      defmodule ReadonlySoftDeleteMCP do
        use Ectomancer, name: "readonly-soft-delete-mcp", version: "1.0.0"

        expose(TestUserSchema, readonly: true, soft_delete: :deleted_at)
      end

      tools = ReadonlySoftDeleteMCP.__components__(:tool)
      tool_names = Enum.map(tools, & &1.name)

      assert "list_test_user_schemas" in tool_names
      refute "restore_test_user_schema" in tool_names
    end
  end

  describe "runtime authorization resolution with server-level global auth" do
    defmodule GlobalDenyMCP do
      use Ectomancer,
        name: "global-deny-mcp",
        version: "1.0.0",
        authorize: fn actor, _action -> actor != nil end

      expose(TestUserSchema, actions: [:create], authorize: nil)
      expose(TestUserSchema, actions: [:update], authorize: :none, as: :public_user)

      expose(TestUserSchema,
        actions: [:destroy],
        authorize: [destroy: :none],
        as: :per_action_user
      )
    end

    alias GlobalDenyMCP.Tool.CreateTestUserSchema
    alias GlobalDenyMCP.Tool.DestroyPerActionUser
    alias GlobalDenyMCP.Tool.UpdatePublicUser

    test "explicit authorize: nil still enforces the server-level global handler" do
      frame = %{assigns: %{ectomancer_actor: nil}}

      assert {:error, %Anubis.MCP.Error{code: -32_001}, _} =
               CreateTestUserSchema.execute(%{}, frame)
    end

    test "authorize: :none skips the server-level global handler" do
      frame = %{assigns: %{ectomancer_actor: nil}}

      assert {:error, %Anubis.MCP.Error{code: code}, _} =
               UpdatePublicUser.execute(%{}, frame)

      refute code == -32_001
    end

    test "per-action :none still enforces the server-level global handler" do
      frame = %{assigns: %{ectomancer_actor: nil}}

      assert {:error, %Anubis.MCP.Error{code: -32_001}, _} =
               DestroyPerActionUser.execute(%{}, frame)
    end
  end

  describe "batch operations" do
    defmodule BatchMCP do
      use Ectomancer, name: "batch-mcp", version: "1.0.0"

      expose(TestUserSchema,
        actions: [:batch_create, :batch_update, :batch_destroy],
        authorize: :none
      )
    end

    alias BatchMCP.Tool.BatchCreateTestUserSchemas
    alias BatchMCP.Tool.BatchDestroyTestUserSchemas
    alias BatchMCP.Tool.BatchUpdateTestUserSchemas

    test "generates batch_create tool" do
      assert Code.ensure_loaded?(BatchCreateTestUserSchemas)
    end

    test "generates batch_update tool" do
      assert Code.ensure_loaded?(BatchUpdateTestUserSchemas)
    end

    test "generates batch_destroy tool" do
      assert Code.ensure_loaded?(BatchDestroyTestUserSchemas)
    end

    test "batch tools have correct names" do
      assert BatchCreateTestUserSchemas.name() == "batch_create_test_user_schemas"
      assert BatchUpdateTestUserSchemas.name() == "batch_update_test_user_schemas"
      assert BatchDestroyTestUserSchemas.name() == "batch_destroy_test_user_schemas"
    end

    test "batch_create has records param as array of objects" do
      schema = BatchCreateTestUserSchemas.input_schema()

      assert %{"type" => "array", "items" => %{"type" => "object"}} =
               schema["properties"]["records"]

      assert "records" in schema["required"]
    end

    test "batch_update has records param as array of objects" do
      schema = BatchUpdateTestUserSchemas.input_schema()

      assert %{"type" => "array", "items" => %{"type" => "object"}} =
               schema["properties"]["records"]

      assert "records" in schema["required"]
    end

    test "batch_destroy has ids param as list" do
      schema = BatchDestroyTestUserSchemas.input_schema()
      assert schema["properties"]["ids"]["type"] == "array"
      assert "ids" in schema["required"]
    end

    test "batch_destroy tool is not generated when not in actions" do
      defmodule NoBatchDestroyMCP do
        use Ectomancer, name: "no-bd-mcp", version: "1.0.0"
        expose(TestUserSchema, actions: [:batch_create], authorize: :none)
      end

      assert Code.ensure_loaded?(NoBatchDestroyMCP.Tool.BatchCreateTestUserSchemas)
      refute Code.ensure_loaded?(NoBatchDestroyMCP.Tool.BatchDestroyTestUserSchemas)
    end

    test "readonly mode excludes batch operations" do
      defmodule ReadonlyBatchMCP do
        use Ectomancer, name: "readonly-batch-mcp", version: "1.0.0"

        expose(TestUserSchema,
          actions: [:list, :batch_create, :batch_update, :batch_destroy],
          readonly: true
        )
      end

      tools = ReadonlyBatchMCP.__components__(:tool)
      tool_names = Enum.map(tools, & &1.name)
      assert "list_test_user_schemas" in tool_names
      refute "batch_create_test_user_schemas" in tool_names
      refute "batch_update_test_user_schemas" in tool_names
      refute "batch_destroy_test_user_schemas" in tool_names
    end

    test "batch_size option is accepted" do
      defmodule BatchSizeMCP do
        use Ectomancer, name: "batch-size-mcp", version: "1.0.0"
        expose(TestUserSchema, actions: [:batch_create], batch_size: 50, authorize: :none)
      end

      assert Code.ensure_loaded?(BatchSizeMCP.Tool.BatchCreateTestUserSchemas)
    end

    test "batch tools have execute function" do
      assert function_exported?(BatchCreateTestUserSchemas, :execute, 2)
      assert function_exported?(BatchUpdateTestUserSchemas, :execute, 2)
      assert function_exported?(BatchDestroyTestUserSchemas, :execute, 2)
    end
  end

  describe "composite primary key support" do
    defmodule CompositeKeyUser do
      use Ecto.Schema

      @primary_key false
      schema "composite_users" do
        field(:tenant_id, :integer, primary_key: true)
        field(:local_id, :integer, primary_key: true)
        field(:name, :string)
      end
    end

    defmodule CompositeKeyMCP do
      use Ectomancer, name: "composite-key-mcp", version: "1.0.0"

      expose(CompositeKeyUser,
        actions: [:get, :update, :destroy, :list, :restore],
        authorize: :none
      )
    end

    alias CompositeKeyMCP.Tool.DestroyCompositeKeyUser
    alias CompositeKeyMCP.Tool.GetCompositeKeyUser
    alias CompositeKeyMCP.Tool.ListCompositeKeyUsers
    alias CompositeKeyMCP.Tool.RestoreCompositeKeyUser
    alias CompositeKeyMCP.Tool.UpdateCompositeKeyUser

    test "get tool has params for all PK fields" do
      schema = GetCompositeKeyUser.input_schema()
      assert schema["properties"]["tenant_id"]["type"] == "integer"
      assert schema["properties"]["local_id"]["type"] == "integer"
      assert "tenant_id" in schema["required"]
      assert "local_id" in schema["required"]
    end

    test "update tool has params for all PK fields" do
      schema = UpdateCompositeKeyUser.input_schema()
      assert schema["properties"]["tenant_id"]["type"] == "integer"
      assert schema["properties"]["local_id"]["type"] == "integer"
      assert "tenant_id" in schema["required"]
      assert "local_id" in schema["required"]
    end

    test "destroy tool has params for all PK fields" do
      schema = DestroyCompositeKeyUser.input_schema()
      assert schema["properties"]["tenant_id"]["type"] == "integer"
      assert schema["properties"]["local_id"]["type"] == "integer"
      assert "tenant_id" in schema["required"]
      assert "local_id" in schema["required"]
    end

    test "restore tool has params for all PK fields" do
      schema = RestoreCompositeKeyUser.input_schema()
      assert schema["properties"]["tenant_id"]["type"] == "integer"
      assert schema["properties"]["local_id"]["type"] == "integer"
      assert "tenant_id" in schema["required"]
      assert "local_id" in schema["required"]
    end

    test "list tool works with composite PK" do
      assert Code.ensure_loaded?(ListCompositeKeyUsers)
      assert function_exported?(ListCompositeKeyUsers, :execute, 2)
    end

    test "get tool is loaded" do
      assert Code.ensure_loaded?(GetCompositeKeyUser)
      assert function_exported?(GetCompositeKeyUser, :execute, 2)
    end

    test "single PK schemas still work identically" do
      schema = GetTestUserSchema.input_schema()
      assert schema["properties"]["id"]["type"] == "integer"
      assert "id" in schema["required"]
      assert schema["required"] == ["id"]
    end
  end
end
