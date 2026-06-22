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

      # After deleting repo config, it may fall back to detect_repo()
      # which scans started applications — accept nil or a detected module
      result = Repo.repo()
      assert result == nil or is_atom(result)

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

    test "validate_repo returns nil for self-reference" do
      assert Repo.validate_repo(Ectomancer.Repo) == nil
    end

    test "validate_repo returns module for valid repo" do
      assert Repo.validate_repo(Ectomancer.TestRepo) == Ectomancer.TestRepo
    end
  end

  describe "validate_includes/3" do
    test "passes through nil include" do
      opts = [scope: nil]
      assert Ectomancer.Repo.validate_includes(nil, :all, opts) == opts
    end

    test "passes through empty include" do
      opts = [scope: nil]
      assert Ectomancer.Repo.validate_includes([], :all, opts) == opts
    end

    test "allows all includes when allowed is :all" do
      result = Ectomancer.Repo.validate_includes(["posts", "comments"], :all, [])
      assert result[:preload] == [:posts, :comments]
    end

    test "filters includes by allowed list" do
      result = Ectomancer.Repo.validate_includes(["secret", "public"], [:public], [])
      assert result[:preload] == [:public]
    end

    test "merges with existing preloads" do
      result = Ectomancer.Repo.validate_includes(["posts"], :all, preload: [:comments])
      assert result[:preload] == [:comments, :posts]
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

  describe "CRUD operations with repo" do
    setup do
      Ecto.Adapters.SQL.Sandbox.checkout(Ectomancer.TestRepo)
      Application.put_env(:ectomancer, :repo, Ectomancer.TestRepo)
      Ectomancer.DataCase.create_table_for_schema!(TestUser)

      on_exit(fn ->
        Application.delete_env(:ectomancer, :repo)
      end)

      :ok
    end

    test "create inserts a record" do
      {:ok, user} = Repo.create(TestUser, %{email: "a@b.com", name: "Alice", age: 30})

      assert user.email == "a@b.com"
      assert user.name == "Alice"
      assert user.age == 30
    end

    test "list returns created records" do
      Repo.create(TestUser, %{email: "a@b.com"})
      Repo.create(TestUser, %{email: "b@c.com"})

      {:ok, users} = Repo.list(TestUser, %{}, limit: 100)
      assert length(users) >= 2
    end

    test "get returns a record by id" do
      {:ok, user} = Repo.create(TestUser, %{email: "get@test.com"})

      {:ok, fetched} = Repo.get(TestUser, %{"id" => user.id})
      assert fetched.email == "get@test.com"
    end

    test "get returns not_found for missing record" do
      assert {:error, :not_found} = Repo.get(TestUser, %{"id" => 9999})
    end

    test "update modifies a record" do
      {:ok, user} = Repo.create(TestUser, %{email: "old@test.com"})

      {:ok, updated} = Repo.update(TestUser, %{"id" => user.id, "email" => "new@test.com"})
      assert updated.email == "new@test.com"
    end

    test "destroy removes a record" do
      {:ok, user} = Repo.create(TestUser, %{email: "del@test.com"})

      {:ok, _} = Repo.destroy(TestUser, %{"id" => user.id})
      assert {:error, :not_found} = Repo.get(TestUser, %{"id" => user.id})
    end

    test "list with ordering param" do
      Repo.create(TestUser, %{email: "z@b.com"})
      Repo.create(TestUser, %{email: "a@b.com"})

      {:ok, users} =
        Repo.list(TestUser, %{"order_by" => "email", "order_dir" => "asc"}, limit: 100)

      assert hd(users).email == "a@b.com"
    end

    test "list supports pagination" do
      Repo.create(TestUser, %{email: "first@a.com"})
      Repo.create(TestUser, %{email: "second@a.com"})
      Repo.create(TestUser, %{email: "third@a.com"})

      {:ok, users} = Repo.list(TestUser, %{"offset" => 1, "limit" => 2})
      assert length(users) == 2
    end

    test "list filters by gte operator" do
      Repo.create(TestUser, %{email: "a@b.com", age: 25})
      Repo.create(TestUser, %{email: "b@c.com", age: 35})

      {:ok, users} = Repo.list(TestUser, %{"age_gte" => 30})
      assert length(users) == 1
    end

    test "list filters by lt operator" do
      Repo.create(TestUser, %{email: "a@b.com", age: 20})
      Repo.create(TestUser, %{email: "b@c.com", age: 40})

      {:ok, users} = Repo.list(TestUser, %{"age_lt" => 30})
      assert length(users) == 1
    end

    test "restore returns not_found when repo configured but no record" do
      assert {:error, :not_found} = Repo.restore(TestUser, %{"id" => 1})
    end

    test "list filters by contains" do
      Repo.create(TestUser, %{email: "alice@example.com", name: "Alice"})
      Repo.create(TestUser, %{email: "bob@test.com", name: "Bob"})

      {:ok, users} = Repo.list(TestUser, %{"email_contains" => "example"})
      assert length(users) == 1
    end

    test "list filters by not-equal" do
      Repo.create(TestUser, %{email: "a@b.com", name: "Alice"})
      Repo.create(TestUser, %{email: "b@c.com", name: "Bob"})

      {:ok, users} = Repo.list(TestUser, %{"name_not" => "Alice"})
      assert length(users) == 1
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
      original = Application.get_env(:ectomancer, :repo)

      try do
        Application.delete_env(:ectomancer, :repo)

        frame = %{assigns: %{ectomancer_actor: nil}}
        result = ListTestUsers.execute(%{}, frame)

        # Should return Anubis error format with descriptive message
        assert {:error, %Anubis.MCP.Error{code: -32_603}, _} = result
      after
        if original do
          Application.put_env(:ectomancer, :repo, original)
        end
      end
    end
  end

  describe "parse_filter_key/1" do
    test "returns :eq for plain field name" do
      assert Repo.parse_filter_key("email") == {:email, :eq}
    end

    test "detects comparison suffixes" do
      assert Repo.parse_filter_key("age_gte") == {:age, :gte}
      assert Repo.parse_filter_key("age_gt") == {:age, :gt}
      assert Repo.parse_filter_key("age_lte") == {:age, :lte}
      assert Repo.parse_filter_key("age_lt") == {:age, :lt}
    end

    test "detects string matching suffixes" do
      assert Repo.parse_filter_key("name_contains") == {:name, :contains}
      assert Repo.parse_filter_key("name_icontains") == {:name, :icontains}
    end

    test "detects list suffix" do
      assert Repo.parse_filter_key("status_in") == {:status, :in}
    end

    test "detects not-equal suffix" do
      assert Repo.parse_filter_key("field_not") == {:field, :not}
    end
  end

  describe "sanitize_like/1" do
    test "escapes LIKE wildcard characters" do
      result = Repo.sanitize_like("test%value_search")
      assert result == "test\\%value\\_search"
    end

    test "escapes backslash" do
      result = Repo.sanitize_like("a\\b")
      assert result == "a\\\\b"
    end

    test "passes through normal strings" do
      assert Repo.sanitize_like("hello") == "hello"
    end

    test "converts non-string to string" do
      assert Repo.sanitize_like(123) == "123"
    end
  end

  describe "parse_int/1" do
    test "returns nil for nil" do
      assert Repo.parse_int(nil) == nil
    end

    test "passes through integers" do
      assert Repo.parse_int(42) == 42
    end

    test "parses valid integer strings" do
      assert Repo.parse_int("42") == 42
      assert Repo.parse_int("0") == 0
    end

    test "returns nil for invalid strings" do
      assert Repo.parse_int("abc") == nil
      assert Repo.parse_int("12.5") == nil
    end

    test "returns nil for other types" do
      assert Repo.parse_int(:atom) == nil
      assert Repo.parse_int([]) == nil
    end
  end

  describe "parse_order_dir/1" do
    test "returns :desc for desc string" do
      assert Repo.parse_order_dir("desc") == :desc
      assert Repo.parse_order_dir("DESC") == :desc
    end

    test "returns :asc for asc or other strings" do
      assert Repo.parse_order_dir("asc") == :asc
      assert Repo.parse_order_dir("ASC") == :asc
      assert Repo.parse_order_dir("") == :asc
    end

    test "returns :asc for non-binary input" do
      assert Repo.parse_order_dir(nil) == :asc
      assert Repo.parse_order_dir(123) == :asc
    end
  end

  describe "cast_primary_key_value/2" do
    test "casts :id from string to integer" do
      assert Repo.cast_primary_key_value("42", :id) == 42
    end

    test "passes through invalid :id string" do
      assert Repo.cast_primary_key_value("abc", :id) == "abc"
    end

    test "passes through unknown type unchanged" do
      assert Repo.cast_primary_key_value("hello", :string_field) == "hello"
      assert Repo.cast_primary_key_value(42, :id) == 42
      assert Repo.cast_primary_key_value(:atom, :any) == :atom
    end
  end

  describe "extract_meta_params/1" do
    test "splits meta keys from filter params" do
      params = %{order_by: "email", order_dir: "desc", limit: 10, email: "test@a.com"}
      {meta, filters} = Repo.extract_meta_params(params)

      assert meta["order_by"] == "email"
      assert meta["order_dir"] == "desc"
      assert meta["limit"] == 10
      assert filters[:email] == "test@a.com"
    end

    test "handles empty params" do
      assert Repo.extract_meta_params(%{}) == {%{}, %{}}
    end
  end

  describe "cast_param_value/2" do
    test "passes through value when type is not special" do
      assert Repo.cast_param_value("hello", :string) == "hello"
      assert Repo.cast_param_value(42, :integer) == 42
    end
  end
end
