defmodule Ectomancer.AuthorizationTest do
  use ExUnit.Case

  alias Ectomancer.Authorization

  describe "check/3" do
    test "returns :ok for :none authorization" do
      assert :ok = Authorization.check(nil, :list, handler: :none)
      assert :ok = Authorization.check(%{}, :get, handler: nil)
    end

    test "returns :ok for inline function returning true" do
      handler = fn _actor, _action -> true end
      assert :ok = Authorization.check(%{}, :list, handler: handler)
    end

    test "returns error for inline function returning false" do
      handler = fn _actor, _action -> false end

      assert {:error, "Unauthorized access to list"} =
               Authorization.check(%{}, :list, handler: handler)
    end

    test "returns :ok for function returning {:ok, true}" do
      handler = fn _actor, _action -> {:ok, true} end
      assert :ok = Authorization.check(%{}, :list, handler: handler)
    end

    test "returns error for function returning {:ok, false}" do
      handler = fn _actor, _action -> {:ok, false} end

      assert {:error, "Unauthorized access to list"} =
               Authorization.check(%{}, :list, handler: handler)
    end

    test "returns error for function returning {:error, reason}" do
      handler = fn _actor, _action -> {:error, "Custom error"} end
      assert {:error, "Custom error"} = Authorization.check(%{}, :list, handler: handler)
    end

    test "works with policy module implementing authorize/2" do
      defmodule TestPolicy2 do
        def authorize(actor, _action) do
          if actor.role == :admin, do: :ok, else: {:error, "Not admin"}
        end
      end

      assert :ok = Authorization.check(%{role: :admin}, :list, handler: TestPolicy2)

      assert {:error, "Not admin"} =
               Authorization.check(%{role: :user}, :list, handler: TestPolicy2)
    end

    test "works with policy module implementing authorize/3" do
      defmodule TestPolicy3 do
        def authorize(actor, _action, _opts) do
          if actor.role == :admin, do: :ok, else: {:error, "Not admin"}
        end
      end

      assert :ok = Authorization.check(%{role: :admin}, :list, handler: TestPolicy3)

      assert {:error, "Not admin"} =
               Authorization.check(%{role: :user}, :list, handler: TestPolicy3)
    end

    test "returns error for missing policy module" do
      assert {:error, "Policy module NonExistent not found"} =
               Authorization.check(%{}, :list, handler: NonExistent)
    end

    test "returns error for policy without authorize function" do
      defmodule NoAuthPolicy do
      end

      assert {:error, message} = Authorization.check(%{}, :list, handler: NoAuthPolicy)
      assert message =~ "does not implement authorize"
    end

    test "cascades parent authorization" do
      parent_handler = fn actor, _action -> actor.role == :admin end
      child_handler = fn actor, _action -> actor.active == true end

      # Both pass
      assert :ok =
               Authorization.check(%{role: :admin, active: true}, :list,
                 handler: child_handler,
                 parent_auth: [handler: parent_handler]
               )

      # Parent fails
      assert {:error, "Unauthorized access to list"} =
               Authorization.check(%{role: :user, active: true}, :list,
                 handler: child_handler,
                 parent_auth: [handler: parent_handler]
               )

      # Child fails
      assert {:error, "Unauthorized access to list"} =
               Authorization.check(%{role: :admin, active: false}, :list,
                 handler: child_handler,
                 parent_auth: [handler: parent_handler]
               )
    end

    test "returns :ok when parent authorization passes and no child" do
      parent_handler = fn actor, _action -> actor.role == :admin end

      assert :ok =
               Authorization.check(%{role: :admin}, :list,
                 handler: nil,
                 parent_auth: [handler: parent_handler]
               )
    end

    test "returns error for invalid handler type" do
      assert {:error, message} = Authorization.check(%{}, :list, handler: "string")
      assert message =~ "Invalid authorization handler"
    end
  end

  describe "enabled?/1" do
    test "returns false for nil handler" do
      refute Authorization.enabled?(handler: nil)
    end

    test "returns false for :none handler" do
      refute Authorization.enabled?(handler: :none)
    end

    test "returns true for function handler" do
      assert Authorization.enabled?(handler: fn _, _ -> true end)
    end

    test "returns true for module handler" do
      assert Authorization.enabled?(handler: SomeModule)
    end

    test "returns true when parent auth is enabled" do
      refute Authorization.enabled?(handler: nil, parent_auth: [handler: nil])
      assert Authorization.enabled?(handler: nil, parent_auth: [handler: fn _, _ -> true end])
    end
  end
end
