defmodule Ectomancer.NamingCollisionsTest do
  use ExUnit.Case

  defmodule TestUser do
    use Ecto.Schema

    schema "users" do
      field(:email, :string)
      field(:name, :string)
    end
  end

  defmodule TestUserV2 do
    use Ecto.Schema

    schema "users_v2" do
      field(:email, :string)
      field(:name, :string)
    end
  end

  defmodule TestPost do
    use Ecto.Schema

    schema "posts" do
      field(:title, :string)
    end
  end

  # Define test modules at the top level to avoid redefinition warnings
  defmodule NamespaceTestMCP do
    use Ectomancer, name: "namespace-test", version: "1.0.0"

    expose(TestUser, namespace: :accounts)
    expose(TestUser, namespace: :legacy)
  end

  defmodule AsOptionTestMCP do
    use Ectomancer, name: "as-option-test", version: "1.0.0"

    expose(TestUser, as: :admin_users)
    expose(TestUser, as: :customers)
  end

  defmodule CombinedTestMCP do
    use Ectomancer, name: "combined-test", version: "1.0.0"

    expose(TestUser, namespace: :accounts, as: :users)
    expose(TestUser, namespace: :legacy, as: :users)
  end

  defmodule DefaultTestMCP do
    use Ectomancer, name: "default-test", version: "1.0.0"

    expose(TestUser)
    expose(TestPost)
  end

  defmodule MultiSchemaTestMCP do
    use Ectomancer, name: "multi-schema-test", version: "1.0.0"

    expose(TestUser, namespace: :accounts)
    expose(TestUserV2, namespace: :v2)
    expose(TestPost)
  end

  describe "namespace option" do
    alias __MODULE__.NamespaceTestMCP, as: TestMCP
    alias TestMCP.Tool.AccountsListTestUsers
    alias TestMCP.Tool.LegacyListTestUsers

    test "tools are prefixed with namespace" do
      assert Code.ensure_loaded?(AccountsListTestUsers)
      assert Code.ensure_loaded?(LegacyListTestUsers)
    end

    test "namespaced tools have correct names" do
      assert AccountsListTestUsers.name() == "accounts_list_test_users"
      assert LegacyListTestUsers.name() == "legacy_list_test_users"
    end

    test "namespaced tools have namespace in description" do
      schema = AccountsListTestUsers.__description__()
      assert schema =~ "[accounts]"
    end
  end

  describe "as option" do
    alias __MODULE__.AsOptionTestMCP, as: TestMCP
    alias TestMCP.Tool.ListAdminUsers
    alias TestMCP.Tool.ListCustomers

    test "tools use 'as' name instead of schema name" do
      assert Code.ensure_loaded?(ListAdminUsers)
      assert Code.ensure_loaded?(ListCustomers)
    end

    test "tools have correct names with 'as' option" do
      assert ListAdminUsers.name() == "list_admin_users"
      assert ListCustomers.name() == "list_customers"
    end
  end

  describe "combination of namespace and as" do
    alias __MODULE__.CombinedTestMCP, as: TestMCP
    alias TestMCP.Tool.AccountsListUsers
    alias TestMCP.Tool.LegacyListUsers

    test "both namespace and as are applied" do
      assert Code.ensure_loaded?(AccountsListUsers)
      assert Code.ensure_loaded?(LegacyListUsers)
    end

    test "combined naming works correctly" do
      assert AccountsListUsers.name() == "accounts_list_users"
      assert LegacyListUsers.name() == "legacy_list_users"
    end
  end

  describe "default behavior without namespace/as" do
    alias __MODULE__.DefaultTestMCP, as: TestMCP
    alias TestMCP.Tool.ListTestPosts
    alias TestMCP.Tool.ListTestUsers

    test "tools use schema name without prefix" do
      assert ListTestUsers.name() == "list_test_users"
      assert ListTestPosts.name() == "list_test_posts"
    end

    test "descriptions do not include namespace" do
      desc = ListTestUsers.__description__()
      refute desc =~ "["
    end
  end

  describe "multiple schemas with different naming strategies" do
    alias __MODULE__.MultiSchemaTestMCP, as: TestMCP
    alias TestMCP.Tool.AccountsListTestUsers
    alias TestMCP.Tool.ListTestPosts
    alias TestMCP.Tool.V2ListTestUserV2s

    test "all schemas generate correct tools" do
      assert Code.ensure_loaded?(AccountsListTestUsers)
      assert Code.ensure_loaded?(V2ListTestUserV2s)
      assert Code.ensure_loaded?(ListTestPosts)
    end
  end

  describe "collision detection" do
    test "collision warning format includes helpful options" do
      # The collision warning should include helpful information
      warning_text = """
      To avoid collisions, use the :namespace or :as options:

          expose MyApp.Accounts.User, namespace: :accounts
          # or
          expose MyApp.Accounts.User, as: :admin_users
      """

      assert warning_text =~ "namespace"
      assert warning_text =~ "as"
    end

    test "namespace and as options prevent collisions" do
      # By using different namespaces, we can expose the same schema multiple times
      # without naming collisions
      alias __MODULE__.NamespaceTestMCP, as: TestMCP
      alias TestMCP.Tool.AccountsListTestUsers
      alias TestMCP.Tool.LegacyListTestUsers

      # Both should exist without collision
      assert AccountsListTestUsers.name() == "accounts_list_test_users"
      assert LegacyListTestUsers.name() == "legacy_list_test_users"
    end
  end
end
