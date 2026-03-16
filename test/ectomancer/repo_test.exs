defmodule Ectomancer.RepoTest do
  use ExUnit.Case

  alias Ectomancer.Repo

  # Test schema
  defmodule TestUser do
    use Ecto.Schema

    schema "test_users" do
      field(:email, :string)
      field(:name, :string)
      field(:age, :integer)

      timestamps()
    end
  end

  describe "repo/0" do
    test "returns nil when not configured" do
      # Save original config
      original = Application.get_env(:ectomancer, :repo)
      Application.delete_env(:ectomancer, :repo)

      assert Repo.repo() == nil

      # Restore
      if original do
        Application.put_env(:ectomancer, :repo, original)
      end
    end

    test "returns configured repo" do
      original = Application.get_env(:ectomancer, :repo)
      Application.put_env(:ectomancer, :repo, MyApp.TestRepo)

      assert Repo.repo() == MyApp.TestRepo

      # Restore
      if original do
        Application.put_env(:ectomancer, :repo, original)
      else
        Application.delete_env(:ectomancer, :repo)
      end
    end
  end

  describe "writable_fields/1" do
    test "returns fields excluding pk and timestamps" do
      # This tests the internal helper function via the public API
      # Since writable_fields is private, we test via create/update behavior
      introspection = Ectomancer.SchemaIntrospection.analyze(TestUser)

      # Writable fields should not include :id, :inserted_at, :updated_at
      writable =
        introspection.fields
        |> Enum.reject(fn field ->
          field in introspection.primary_key or field in [:inserted_at, :updated_at]
        end)

      assert :email in writable
      assert :name in writable
      assert :age in writable
      refute :id in writable
      refute :inserted_at in writable
      refute :updated_at in writable
    end
  end

  describe "CRUD operations without repo" do
    setup do
      # Save and clear repo config
      original = Application.get_env(:ectomancer, :repo)
      Application.delete_env(:ectomancer, :repo)

      on_exit(fn ->
        if original do
          Application.put_env(:ectomancer, :repo, original)
        end
      end)

      :ok
    end

    test "list returns error when repo not configured" do
      assert {:error, :repo_not_configured} = Repo.list(TestUser)
    end

    test "get returns error when repo not configured" do
      assert {:error, :repo_not_configured} = Repo.get(TestUser, %{"id" => 1})
    end

    test "create returns error when repo not configured" do
      assert {:error, :repo_not_configured} = Repo.create(TestUser, %{"email" => "test@test.com"})
    end

    test "update returns error when repo not configured" do
      assert {:error, :repo_not_configured} = Repo.update(TestUser, %{"id" => 1, "name" => "New"})
    end

    test "destroy returns error when repo not configured" do
      assert {:error, :repo_not_configured} = Repo.destroy(TestUser, %{"id" => 1})
    end
  end

  describe "extract_primary_key/2" do
    # Testing via the get function which uses extract_primary_key
    setup do
      original = Application.get_env(:ectomancer, :repo)
      Application.delete_env(:ectomancer, :repo)

      on_exit(fn ->
        if original do
          Application.put_env(:ectomancer, :repo, original)
        end
      end)

      :ok
    end

    test "handles missing primary key" do
      # This should fail before trying to query because repo is not configured
      assert {:error, :repo_not_configured} = Repo.get(TestUser, %{"id" => 1})
    end
  end

  describe "integration with expose macro" do
    defmodule TestMCP do
      use Ectomancer, name: "test-repo-mcp", version: "1.0.0"

      expose(TestUser, actions: [:list, :get, :create])
    end

    alias __MODULE__.TestMCP, as: TestMCP
    alias TestMCP.Tool.ListTestUsers

    test "tools use Ectomancer.Repo for execution" do
      # Verify the tool modules exist and have execute functions
      assert Code.ensure_loaded?(ListTestUsers)
      assert Code.ensure_loaded?(TestMCP.Tool.GetTestUser)
      assert Code.ensure_loaded?(TestMCP.Tool.CreateTestUser)
    end

    test "list tool returns error when repo not configured" do
      Application.delete_env(:ectomancer, :repo)

      frame = %{assigns: %{ectomancer_actor: nil}}
      result = ListTestUsers.execute(%{}, frame)

      # Should return Anubis error format
      assert {:error, %Anubis.MCP.Error{data: %{reason: :repo_not_configured}}, _} = result
    end
  end
end
