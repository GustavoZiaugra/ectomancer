defmodule Ectomancer.FieldAuthTest do
  use Ectomancer.DataCase,
    schemas: [Ectomancer.FieldAuthTest.User]

  alias Ectomancer.TestRepo

  defmodule User do
    use Ecto.Schema

    schema "field_auth_users" do
      field(:email, :string)
      field(:name, :string)
      field(:password_hash, :string)
      field(:salary, :integer)
      timestamps()
    end
  end

  defmodule AdminMCP do
    use Ectomancer, name: "field-auth-admin", version: "1.0.0"

    expose(User,
      actions: [:list, :get],
      field_authorize: fn _actor, _field -> true end
    )
  end

  defmodule UserMCP do
    use Ectomancer, name: "field-auth-user", version: "1.0.0"

    expose(User,
      actions: [:list, :get],
      field_authorize: fn actor, field ->
        cond do
          field in [:password_hash, :salary] -> actor.role == :admin
          true -> true
        end
      end
    )
  end

  setup do
    Application.put_env(:ectomancer, :repo, TestRepo)
    Ectomancer.DataCase.create_table_for_schema!(User)

    Ectomancer.DataCase.insert!(User, %{
      email: "admin@test.com",
      name: "Admin User",
      password_hash: "admin_secret",
      salary: 100_000
    })

    Ectomancer.DataCase.insert!(User, %{
      email: "user@test.com",
      name: "Regular User",
      password_hash: "user_secret",
      salary: 50_000
    })

    on_exit(fn ->
      Application.delete_env(:ectomancer, :repo)
    end)

    :ok
  end

  describe "Ectomancer.FieldAuth.filter_fields/3" do
    test "returns all fields when auth_fn returns true for all" do
      user = %User{email: "a@b.com", name: "Test", password_hash: "secret", salary: 100}
      result = Ectomancer.FieldAuth.filter_fields(user, %{}, fn _, _ -> true end)
      assert result.email == "a@b.com"
      assert result.password_hash == "secret"
      assert result.salary == 100
    end

    test "filters out sensitive fields" do
      user = %User{email: "a@b.com", name: "Test", password_hash: "secret", salary: 100}

      result =
        Ectomancer.FieldAuth.filter_fields(user, %{role: :user}, fn actor, field ->
          if field in [:password_hash, :salary], do: actor.role == :admin, else: true
        end)

      assert result.email == "a@b.com"
      assert result.name == "Test"
      refute Map.has_key?(result, :password_hash)
      refute Map.has_key?(result, :salary)
    end

    test "admin sees all fields" do
      user = %User{email: "a@b.com", name: "Test", password_hash: "secret", salary: 100}

      result =
        Ectomancer.FieldAuth.filter_fields(user, %{role: :admin}, fn actor, field ->
          if field in [:password_hash, :salary], do: actor.role == :admin, else: true
        end)

      assert result.email == "a@b.com"
      assert result.password_hash == "secret"
      assert result.salary == 100
    end

    test "works with lists" do
      users = [
        %User{email: "a@b.com", password_hash: "s1", salary: 100},
        %User{email: "c@d.com", password_hash: "s2", salary: 200}
      ]

      result =
        Ectomancer.FieldAuth.filter_fields(users, %{role: :user}, fn actor, field ->
          if field in [:password_hash, :salary], do: actor.role == :admin, else: true
        end)

      assert length(result) == 2

      Enum.each(result, fn u ->
        assert u.email
        refute Map.has_key?(u, :password_hash)
        refute Map.has_key?(u, :salary)
      end)
    end

    test "nil auth_fn returns data unchanged" do
      user = %User{email: "a@b.com"}
      assert Ectomancer.FieldAuth.filter_fields(user, %{}, nil) == user
    end
  end

  describe "expose macro with field_authorize" do
    test "admin MCP generates tools with field_authorize" do
      assert {:module, _} = Code.ensure_loaded(AdminMCP.Tool.ListUsers)
      assert {:module, _} = Code.ensure_loaded(AdminMCP.Tool.GetUser)
    end

    test "user MCP generates tools with field_authorize" do
      assert {:module, _} = Code.ensure_loaded(UserMCP.Tool.ListUsers)
      assert {:module, _} = Code.ensure_loaded(UserMCP.Tool.GetUser)
    end
  end

  describe "tool execution with field_authorize" do
    test "admin sees sensitive fields" do
      frame = %{assigns: %{ectomancer_actor: %{role: :admin}}}
      {:reply, response, _frame} = UserMCP.Tool.GetUser.execute(%{"id" => 1}, frame)
      text = response.content |> List.first() |> Map.get("text")
      assert text =~ "password_hash"
      assert text =~ "salary"
    end

    test "regular user does not see sensitive fields" do
      frame = %{assigns: %{ectomancer_actor: %{role: :user}}}
      {:reply, response, _frame} = UserMCP.Tool.GetUser.execute(%{"id" => 1}, frame)
      text = response.content |> List.first() |> Map.get("text")
      refute text =~ "password_hash"
      refute text =~ "salary"
      assert text =~ "admin@test.com"
    end

    test "list respects field_authorize" do
      frame = %{assigns: %{ectomancer_actor: %{role: :user}}}
      {:reply, response, _frame} = UserMCP.Tool.ListUsers.execute(%{}, frame)
      text = response.content |> List.first() |> Map.get("text")
      refute text =~ "password_hash"
      refute text =~ "salary"
      assert text =~ "user@test.com"
      assert text =~ "admin@test.com"
    end
  end
end
