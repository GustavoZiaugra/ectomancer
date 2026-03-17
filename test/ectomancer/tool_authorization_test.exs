defmodule Ectomancer.ToolAuthorizationTest do
  use ExUnit.Case

  defmodule TestMCP do
    use Ectomancer, name: "test-mcp", version: "1.0.0"

    # Tool with inline authorization
    tool :admin_only do
      description("Admin only action")

      authorize(fn actor, _action ->
        actor.role == :admin
      end)

      handle(fn _params, _actor ->
        {:ok, "Secret data"}
      end)
    end

    # Tool with no authorization (public)
    tool :public_action do
      description("Public action")

      authorize(:none)

      handle(fn _params, _actor ->
        {:ok, "Public data"}
      end)
    end

    # Tool with inline authorization function
    tool :with_policy do
      description("Uses inline auth")

      authorize(fn actor, _action -> actor.role == :admin end)

      handle(fn _params, _actor ->
        {:ok, "Protected data"}
      end)
    end

    # Tool with default (no authorize block)
    tool :default_auth do
      description("Default auth")

      handle(fn _params, _actor ->
        {:ok, "Default data"}
      end)
    end
  end

  alias TestMCP.Tool.{AdminOnly, PublicAction, WithPolicy, DefaultAuth}

  describe "tool with inline authorization" do
    test "allows access for admin" do
      frame = %{assigns: %{ectomancer_actor: %{role: :admin}}}

      assert {:reply, response, _} = AdminOnly.execute(%{}, frame)
      assert response.content == [%{"type" => "text", "text" => ~s("Secret data")}]
    end

    test "denies access for non-admin" do
      frame = %{assigns: %{ectomancer_actor: %{role: :user}}}

      assert {:error, error, _} = AdminOnly.execute(%{}, frame)
      assert error.code == -32_001
      assert error.message =~ "Unauthorized"
    end
  end

  describe "tool with :none authorization" do
    test "allows access for any actor" do
      frame = %{assigns: %{ectomancer_actor: %{role: :anonymous}}}

      assert {:reply, response, _} = PublicAction.execute(%{}, frame)
      assert response.content == [%{"type" => "text", "text" => ~s("Public data")}]
    end

    test "allows access with nil actor" do
      frame = %{assigns: %{}}

      assert {:reply, response, _} = PublicAction.execute(%{}, frame)
      assert response.content == [%{"type" => "text", "text" => ~s("Public data")}]
    end
  end

  describe "tool with policy module" do
    test "allows access when policy returns :ok" do
      frame = %{assigns: %{ectomancer_actor: %{role: :admin}}}

      assert {:reply, response, _} = WithPolicy.execute(%{}, frame)
      assert response.content == [%{"type" => "text", "text" => ~s("Protected data")}]
    end

    test "denies access when policy returns error" do
      frame = %{assigns: %{ectomancer_actor: %{role: :user}}}

      assert {:error, error, _} = WithPolicy.execute(%{}, frame)
      assert error.code == -32_001
      assert error.message =~ "Unauthorized"
    end
  end

  describe "tool with default authorization" do
    test "allows access when no authorize block" do
      frame = %{assigns: %{ectomancer_actor: %{role: :any}}}

      assert {:reply, response, _} = DefaultAuth.execute(%{}, frame)
      assert response.content == [%{"type" => "text", "text" => ~s("Default data")}]
    end
  end
end
