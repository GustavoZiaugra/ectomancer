defmodule Ectomancer.PostgresScopeTest do
  @moduledoc """
  Postgres-only integration tests for `scope:` enforcement on writes.

  SQLite cannot exercise the mechanisms these tests cover, because a failed
  statement does not abort a SQLite transaction while it does on Postgres:

    * `mode: :savepoint` containment — batch operations rely on the adapter
      honoring `mode: :savepoint` so one failing record does not abort the
      whole batch transaction
    * rollback / undo / restore semantics against real Postgres errors

  Run with:

      ECTOMANCER_PG_URL=postgres://postgres:postgres@localhost:5432/ectomancer_test \\
        mix test --only postgres
  """

  use ExUnit.Case, async: false

  @moduletag :postgres

  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox
  alias Ectomancer.PostgresRepo

  defmodule Item do
    use Ecto.Schema

    schema "pg_scope_items" do
      field(:name, :string)
      field(:tenant_id, :integer)
    end
  end

  defmodule ScopedMCP do
    use Ectomancer, name: "pg-scope-mcp", version: "1.0.0"

    expose(Item,
      actions: [:list, :create, :update, :batch_create, :batch_update],
      authorize: :none,
      scope: fn query, actor ->
        import Ecto.Query
        from(t in query, where: t.tenant_id == ^actor.tenant_id)
      end
    )
  end

  alias ScopedMCP.Tool.BatchCreateItems, as: BatchCreate
  alias ScopedMCP.Tool.BatchUpdateItems, as: BatchUpdate
  alias ScopedMCP.Tool.CreateItem, as: Create

  setup do
    :ok = Sandbox.checkout(PostgresRepo)

    # DDL runs inside the sandbox transaction and is rolled back at check-in.
    SQL.query!(PostgresRepo, """
    CREATE TABLE pg_scope_items (
      id BIGSERIAL PRIMARY KEY,
      name TEXT,
      tenant_id BIGINT
    )
    """)

    Application.put_env(:ectomancer, :repo, PostgresRepo)

    on_exit(fn -> Application.delete_env(:ectomancer, :repo) end)

    :ok
  end

  describe "savepoint containment" do
    test "batch_create keeps the transaction usable after a DB-level failure" do
      SQL.query!(
        PostgresRepo,
        "CREATE UNIQUE INDEX pg_scope_items_name_unique ON pg_scope_items (name)"
      )

      SQL.query!(PostgresRepo, "INSERT INTO pg_scope_items (name, tenant_id) VALUES ('dup', 1)")

      text =
        reply_text(
          BatchCreate,
          %{
            "records" => [
              %{"name" => "dup", "tenant_id" => 1},
              %{"name" => "own", "tenant_id" => 1}
            ]
          },
          1
        )

      # The duplicate raises a constraint error (no declared constraint on the
      # changeset); without `mode: :savepoint` Postgres would abort the whole
      # transaction and the second insert would fail with 25P02.
      assert text =~ "\"succeeded\""
      assert names() == ["dup", "own"]
    end
  end

  describe "scope enforcement on single writes" do
    test "create rolls back an out-of-scope row" do
      assert {:error, %Anubis.MCP.Error{message: message}, _} =
               Create.execute(%{"name" => "smuggled", "tenant_id" => 2}, frame(1))

      assert message =~ "not found"
      assert count() == 0
    end

    test "create commits an in-scope row" do
      assert {:reply, _, _} = Create.execute(%{"name" => "own", "tenant_id" => 1}, frame(1))
      assert names() == ["own"]
    end
  end

  describe "scope enforcement on batch writes" do
    test "batch_create undoes the out-of-scope row and commits the valid one" do
      text =
        reply_text(
          BatchCreate,
          %{
            "records" => [
              %{"name" => "own", "tenant_id" => 1},
              %{"name" => "smuggled", "tenant_id" => 2}
            ]
          },
          1
        )

      assert text =~ "scope_violation"
      assert names() == ["own"]
    end

    test "batch_update restores a row moved out of the actor's scope" do
      %{rows: [[id]]} =
        SQL.query!(
          PostgresRepo,
          "INSERT INTO pg_scope_items (name, tenant_id) VALUES ('mine', 1) RETURNING id"
        )

      text =
        reply_text(
          BatchUpdate,
          %{"records" => [%{"id" => id, "tenant_id" => 2, "name" => "moved"}]},
          1
        )

      assert text =~ "scope_violation"
      assert names() == ["mine"]
      assert tenant_of("mine") == 1
    end
  end

  describe "scope safety net failures" do
    test "batch_create aborts the whole batch when the undo delete is blocked" do
      SQL.query!(PostgresRepo, """
      CREATE FUNCTION pg_scope_block_delete() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'delete blocked';
      END;
      $$ LANGUAGE plpgsql
      """)

      SQL.query!(PostgresRepo, """
      CREATE TRIGGER pg_scope_items_block_delete
      BEFORE DELETE ON pg_scope_items
      FOR EACH ROW EXECUTE FUNCTION pg_scope_block_delete()
      """)

      assert {:error, %Anubis.MCP.Error{message: message}, _} =
               BatchCreate.execute(
                 %{
                   "records" => [
                     %{"name" => "own", "tenant_id" => 1},
                     %{"name" => "smuggled", "tenant_id" => 2}
                   ]
                 },
                 frame(1)
               )

      assert message =~ "failed"
      assert count() == 0
    end
  end

  defp frame(tenant_id), do: %{assigns: %{ectomancer_actor: %{tenant_id: tenant_id}}}

  defp reply_text(tool, params, actor) do
    case tool.execute(params, frame(actor)) do
      {:reply, %Anubis.Server.Response{content: [%{"text" => text}]}, _} ->
        text

      other ->
        flunk("Expected reply, got: #{inspect(other)}")
    end
  end

  defp count do
    %{rows: [[count]]} = SQL.query!(PostgresRepo, "SELECT COUNT(*) FROM pg_scope_items")
    count
  end

  defp names do
    %{rows: rows} = SQL.query!(PostgresRepo, "SELECT name FROM pg_scope_items ORDER BY name")
    List.flatten(rows)
  end

  defp tenant_of(name) do
    %{rows: [[tenant_id]]} =
      SQL.query!(PostgresRepo, "SELECT tenant_id FROM pg_scope_items WHERE name = $1", [name])

    tenant_id
  end
end
