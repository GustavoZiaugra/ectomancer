defmodule Ectomancer.SQLToolTest do
  use ExUnit.Case

  alias Ectomancer.SQLTool

  setup do
    # Save original config
    original_config = Application.get_env(:ectomancer, :sql_execution)

    on_exit(fn ->
      if original_config do
        Application.put_env(:ectomancer, :sql_execution, original_config)
      else
        Application.delete_env(:ectomancer, :sql_execution)
      end
    end)

    :ok
  end

  describe "enabled?/0" do
    test "returns false when not configured" do
      Application.delete_env(:ectomancer, :sql_execution)
      assert SQLTool.enabled?() == false
    end

    test "returns false when disabled" do
      Application.put_env(:ectomancer, :sql_execution, enabled: false)
      assert SQLTool.enabled?() == false
    end

    test "returns true when enabled" do
      Application.put_env(:ectomancer, :sql_execution, enabled: true)
      assert SQLTool.enabled?() == true
    end
  end

  describe "config/0" do
    test "returns default values when not configured" do
      Application.delete_env(:ectomancer, :sql_execution)
      config = SQLTool.config()

      assert config[:enabled] == false
      assert config[:max_rows] == 100
      assert config[:read_only] == true
      assert config[:allowed_repos] == []
    end

    test "returns configured values" do
      Application.put_env(:ectomancer, :sql_execution,
        enabled: true,
        max_rows: 50,
        read_only: false
      )

      config = SQLTool.config()

      assert config[:enabled] == true
      assert config[:max_rows] == 50
      assert config[:read_only] == false
    end
  end

  describe "execute/2" do
    test "returns error when SQL execution is disabled" do
      Application.put_env(:ectomancer, :sql_execution, enabled: false)

      assert {:error, :sql_execution_disabled} = SQLTool.execute("SELECT 1")
    end

    test "returns error when repo is not configured" do
      Application.put_env(:ectomancer, :sql_execution, enabled: true)
      Application.delete_env(:ectomancer, :repo)

      assert {:error, :repo_not_configured} = SQLTool.execute("SELECT 1")
    end
  end

  describe "valid_query?/1" do
    setup do
      Application.put_env(:ectomancer, :sql_execution, read_only: true)
    end

    test "returns true for SELECT queries in read-only mode" do
      assert SQLTool.valid_query?("SELECT * FROM users") == true
      assert SQLTool.valid_query?("  select id from posts") == true
    end

    test "returns false for INSERT in read-only mode" do
      assert SQLTool.valid_query?("INSERT INTO users (email) VALUES ('test')") == false
    end

    test "returns false for UPDATE in read-only mode" do
      assert SQLTool.valid_query?("UPDATE users SET email = 'test'") == false
    end

    test "returns false for DELETE in read-only mode" do
      assert SQLTool.valid_query?("DELETE FROM users") == false
    end

    test "returns false for DROP in read-only mode" do
      assert SQLTool.valid_query?("DROP TABLE users") == false
    end

    test "returns false for ALTER in read-only mode" do
      assert SQLTool.valid_query?("ALTER TABLE users ADD COLUMN age") == false
    end

    test "returns false for TRUNCATE in read-only mode" do
      assert SQLTool.valid_query?("TRUNCATE TABLE users") == false
    end

    test "returns false for CREATE in read-only mode" do
      assert SQLTool.valid_query?("CREATE TABLE test (id int)") == false
    end

    test "returns true for any query when not in read-only mode" do
      Application.put_env(:ectomancer, :sql_execution, read_only: false)

      assert SQLTool.valid_query?("INSERT INTO users (email) VALUES ('test')") == true
      assert SQLTool.valid_query?("DELETE FROM users") == true
      assert SQLTool.valid_query?("SELECT * FROM users") == true
    end
  end

  describe "select_query?/1 (private)" do
    # Testing via valid_query? since select_query? is private
    test "identifies SELECT queries correctly" do
      Application.put_env(:ectomancer, :sql_execution, read_only: true)

      assert SQLTool.valid_query?("SELECT * FROM users") == true
      assert SQLTool.valid_query?("select id, email from users") == true
      assert SQLTool.valid_query?("SELECT count(*) FROM users") == true
    end

    test "identifies non-SELECT queries in read-only mode" do
      Application.put_env(:ectomancer, :sql_execution, read_only: true)

      assert SQLTool.valid_query?("INSERT INTO users VALUES (1)") == false
      assert SQLTool.valid_query?("UPDATE users SET x = 1") == false
      assert SQLTool.valid_query?("DELETE FROM users") == false
    end
  end
end
