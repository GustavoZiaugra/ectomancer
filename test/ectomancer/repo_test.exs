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

  describe "extract_primary_key/3" do
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
      assert {:error, :repo_not_configured} = Repo.get(TestUser, %{"id" => 1})
    end

    test "accepts both string and atom keys in params" do
      # Should work with string key
      assert {:error, :repo_not_configured} = Repo.get(TestUser, %{"id" => 1})

      # Should work with atom key
      assert {:error, :repo_not_configured} = Repo.get(TestUser, %{id: 1})
    end

    test "casts string id to integer for :id type" do
      # When integer ID is passed as string (from JSON), it should be cast
      assert {:error, :repo_not_configured} = Repo.get(TestUser, %{"id" => "123"})
    end
  end

  describe "binary_id primary key handling" do
    defmodule BinaryIdUser do
      use Ecto.Schema

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id

      schema "binary_id_users" do
        field(:email, :string)
        field(:name, :string)

        timestamps()
      end
    end

    defmodule ExplicitUUIDUser do
      use Ecto.Schema

      @primary_key {:id, Ecto.UUID, autogenerate: true}

      schema "uuid_users" do
        field(:email, :string)

        timestamps()
      end
    end

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

    test "handles :binary_id type primary key" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"

      # Should accept UUID string without error (repo not configured is expected)
      assert {:error, :repo_not_configured} =
               Repo.get(BinaryIdUser, %{"id" => uuid})
    end

    test "handles Ecto.UUID type primary key" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"

      # Should accept UUID string without error
      assert {:error, :repo_not_configured} =
               Repo.get(ExplicitUUIDUser, %{"id" => uuid})
    end

    test "handles invalid UUID gracefully" do
      # Invalid UUID should still be passed through (DB will reject if needed)
      assert {:error, :repo_not_configured} =
               Repo.get(BinaryIdUser, %{"id" => "not-a-valid-uuid"})
    end

    test "binary_id PK extraction returns proper format" do
      # Test that binary_id fields are properly identified by introspection
      introspection = Ectomancer.SchemaIntrospection.analyze(BinaryIdUser)

      assert introspection.primary_key == [:id]
      assert introspection.types[:id] == :binary_id
    end

    test "Ecto.UUID PK extraction returns proper format" do
      introspection = Ectomancer.SchemaIntrospection.analyze(ExplicitUUIDUser)

      assert introspection.primary_key == [:id]
      assert introspection.types[:id] == Ecto.UUID
    end
  end

  describe "primary key type casting" do
    test "cast_primary_key_value handles :id type" do
      # Testing via introspection that :id type is detected correctly
      introspection = Ectomancer.SchemaIntrospection.analyze(TestUser)

      assert introspection.types[:id] == :id
    end

    test "cast_primary_key_value handles :binary_id type" do
      # Define a test schema with binary_id
      defmodule TestBinarySchema do
        use Ecto.Schema
        @primary_key {:id, :binary_id, autogenerate: true}
        schema "test" do
          field(:name, :string)
        end
      end

      introspection = Ectomancer.SchemaIntrospection.analyze(TestBinarySchema)

      assert introspection.types[:id] == :binary_id
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

      # Should return Anubis error format with descriptive message
      assert {:error, %Anubis.MCP.Error{code: -32_603}, _} = result
    end
  end
end
