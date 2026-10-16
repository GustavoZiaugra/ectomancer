defmodule Ectomancer.ScopeWriteEnforcementTest do
  @moduledoc """
  Tests that `scope:` is enforced on write paths, not just reads (#174):

    * create/upsert/batch_create rows are re-selected through the scope after
      insert and rolled back when the resulting row is not visible
    * update/batch_update rows are re-checked after the write and rolled back
      when the update moved the row out of the actor's scope
    * `order_by` is resolved against exposed/filterable fields, not every
      schema field
  """

  use Ectomancer.DataCase

  alias Ectomancer.ScopeWriteEnforcementTest.RedactedOrderMCP.Tool, as: RedactedTool
  alias Ectomancer.ScopeWriteEnforcementTest.ScopedWriteMCP.Tool, as: ScopedTool
  alias Ectomancer.TestRepo

  defmodule TenantItem do
    use Ecto.Schema

    schema "tenant_items" do
      field(:name, :string)
      field(:tenant_id, :integer)
      field(:secret, :string)

      timestamps()
    end
  end

  defmodule PkLessItem do
    use Ecto.Schema

    @primary_key false
    schema "pk_less_items" do
      field(:name, :string)
      field(:tenant_id, :integer)
    end
  end

  @moduletag schemas: [TenantItem, PkLessItem]

  setup %{repo: _repo} do
    Application.put_env(:ectomancer, :repo, TestRepo)

    on_exit(fn ->
      Application.delete_env(:ectomancer, :repo)
    end)

    :ok
  end

  defmodule ScopedWriteMCP do
    use Ectomancer, name: "scoped-write-mcp", version: "1.0.0"

    expose(TenantItem,
      actions: [:list, :get, :create, :update, :batch_create, :batch_update],
      authorize: :none,
      scope: fn query, actor ->
        import Ecto.Query
        from(t in query, where: t.tenant_id == ^actor.tenant_id)
      end
    )
  end

  defmodule RedactedOrderMCP do
    use Ectomancer, name: "redacted-order-mcp", version: "1.0.0"

    expose(TenantItem, actions: [:list], except: [:secret])
  end

  defmodule PkLessMCP do
    use Ectomancer, name: "pk-less-mcp", version: "1.0.0"

    expose(PkLessItem,
      actions: [:create, :list],
      authorize: :none,
      scope: fn query, actor ->
        import Ecto.Query
        from(t in query, where: t.tenant_id == ^actor.tenant_id)
      end
    )
  end

  defp frame(tenant_id), do: %{assigns: %{ectomancer_actor: %{tenant_id: tenant_id}}}

  defp tenant_one_scope do
    fn query ->
      import Ecto.Query
      from(t in query, where: t.tenant_id == 1)
    end
  end

  defp reply_text(tool, params, actor) do
    case tool.execute(params, frame(actor)) do
      {:reply, %Anubis.Server.Response{content: [%{"text" => text}]}, _} ->
        text

      other ->
        flunk("Expected reply, got: #{inspect(other)}")
    end
  end

  describe "scope enforcement on single writes" do
    test "create rolls back a row written under another tenant" do
      assert {:error, %Anubis.MCP.Error{message: message}, _} =
               ScopedTool.CreateTenantItem.execute(
                 %{"name" => "smuggled", "tenant_id" => 2},
                 frame(1)
               )

      assert message =~ "not found"
      {:ok, rows} = Ectomancer.Repo.list(TenantItem, %{})
      assert rows == []
    end

    test "create succeeds when the row stays inside the actor's scope" do
      assert {:reply, _, _} =
               ScopedTool.CreateTenantItem.execute(
                 %{"name" => "own", "tenant_id" => 1},
                 frame(1)
               )

      {:ok, rows} = Ectomancer.Repo.list(TenantItem, %{})
      assert [%{name: "own", tenant_id: 1}] = rows
    end

    test "update rolls back a row moved to another tenant" do
      insert!(TenantItem, %{name: "mine", tenant_id: 1})

      {:ok, [row]} = Ectomancer.Repo.list(TenantItem, %{"name" => "mine"})

      assert {:error, %Anubis.MCP.Error{message: message}, _} =
               ScopedTool.UpdateTenantItem.execute(
                 %{"id" => row.id, "tenant_id" => 2},
                 frame(1)
               )

      assert message =~ "not found"

      # The row is unchanged and still in tenant 1
      {:ok, [unchanged]} = Ectomancer.Repo.list(TenantItem, %{"name" => "mine"})
      assert unchanged.tenant_id == 1
    end
  end

  describe "scope enforcement on batch writes" do
    test "batch_create reports an out-of-scope row as failed and commits the valid one" do
      text =
        reply_text(
          ScopedTool.BatchCreateTenantItems,
          %{
            "records" => [
              %{"name" => "own", "tenant_id" => 1},
              %{"name" => "smuggled", "tenant_id" => 2}
            ]
          },
          1
        )

      assert text =~ "\"succeeded\""
      assert text =~ "scope_violation"

      {:ok, rows} = Ectomancer.Repo.list(TenantItem, %{})
      assert [%{name: "own", tenant_id: 1}] = rows
    end

    test "batch_update restores a row moved out of the actor's scope" do
      insert!(TenantItem, %{name: "mine", tenant_id: 1})
      {:ok, [row]} = Ectomancer.Repo.list(TenantItem, %{"name" => "mine"})

      text =
        reply_text(
          ScopedTool.BatchUpdateTenantItems,
          %{
            "records" => [
              %{"id" => row.id, "tenant_id" => 2, "name" => "moved"}
            ]
          },
          1
        )

      assert text =~ "scope_violation"

      {:ok, [unchanged]} = Ectomancer.Repo.list(TenantItem, %{"name" => "mine"})
      assert unchanged.tenant_id == 1
    end
  end

  describe "order_by allowlist" do
    setup do
      insert!(TenantItem, %{name: "first-row", tenant_id: 1, secret: "b"})
      insert!(TenantItem, %{name: "second-row", tenant_id: 1, secret: "a"})
      :ok
    end

    test "order_by on an except: field is ignored" do
      # secret "a" sorts before "b": if the hidden field were orderable,
      # ascending order would put "second-row" (secret "a") first.
      text = reply_text(RedactedTool.ListTenantItems, %{"order_by" => "secret"}, nil)

      assert String.contains?(text, "first-row")
      assert String.contains?(text, "second-row")
      assert :binary.match(text, "first-row") < :binary.match(text, "second-row")

      # The field value itself stays redacted
      refute text =~ "\"secret\""
    end

    test "order_by on an exposed field still works" do
      text =
        reply_text(
          RedactedTool.ListTenantItems,
          %{"order_by" => "name", "order_dir" => "desc"},
          nil
        )

      assert :binary.match(text, "second-row") < :binary.match(text, "first-row")
    end

    test "order_by on a timestamp still works when except: hides another field" do
      insert!(TenantItem, %{
        name: "old-row",
        tenant_id: 1,
        secret: "z",
        inserted_at: ~N[2026-01-01 00:00:00]
      })

      insert!(TenantItem, %{
        name: "new-row",
        tenant_id: 1,
        secret: "a",
        inserted_at: ~N[2026-01-02 00:00:00]
      })

      text =
        reply_text(
          RedactedTool.ListTenantItems,
          %{"order_by" => "inserted_at", "order_dir" => "desc"},
          nil
        )

      assert :binary.match(text, "new-row") < :binary.match(text, "old-row")
    end
  end

  describe "scope safety net failures" do
    alias Ecto.Adapters.SQL

    test "batch_create aborts the whole batch when the undo delete is blocked" do
      SQL.query!(
        TestRepo,
        "CREATE TRIGGER block_tenant_item_delete BEFORE DELETE ON tenant_items " <>
          "BEGIN SELECT RAISE(ABORT, 'delete blocked'); END"
      )

      assert {:error, %Anubis.MCP.Error{message: message}, _} =
               ScopedTool.BatchCreateTenantItems.execute(
                 %{
                   "records" => [
                     %{"name" => "own", "tenant_id" => 1},
                     %{"name" => "smuggled", "tenant_id" => 2}
                   ]
                 },
                 frame(1)
               )

      assert message =~ "failed"
      assert count(TenantItem) == 0
    end

    test "batch_update aborts the whole batch when the restore update is blocked" do
      insert!(TenantItem, %{name: "mine", tenant_id: 1})
      {:ok, [row]} = Ectomancer.Repo.list(TenantItem, %{"name" => "mine"})

      # Only blocks the restore write (back to tenant 1), not the update to tenant 2
      SQL.query!(
        TestRepo,
        "CREATE TRIGGER block_tenant_item_restore BEFORE UPDATE ON tenant_items " <>
          "WHEN NEW.tenant_id = 1 BEGIN SELECT RAISE(ABORT, 'restore blocked'); END"
      )

      assert {:error, %Anubis.MCP.Error{message: message}, _} =
               ScopedTool.BatchUpdateTenantItems.execute(
                 %{"records" => [%{"id" => row.id, "tenant_id" => 2, "name" => "moved"}]},
                 frame(1)
               )

      assert message =~ "failed"

      # Whole transaction rolled back: the row is still in tenant 1, unchanged
      {:ok, [unchanged]} = Ectomancer.Repo.list(TenantItem, %{"name" => "mine"})
      assert unchanged.tenant_id == 1
    end
  end

  describe "scope enforcement on upsert" do
    test "upsert insert path rolls back an out-of-scope insert" do
      assert {:error, :scope_violation} =
               Ectomancer.Repo.upsert(
                 TenantItem,
                 %{"name" => "smuggled", "tenant_id" => 2},
                 conflict_target: :name,
                 scope: tenant_one_scope(),
                 repo: TestRepo
               )

      assert count(TenantItem) == 0
    end

    test "upsert insert path commits an in-scope insert" do
      assert {:ok, {%{name: "own", tenant_id: 1}, :inserted}} =
               Ectomancer.Repo.upsert(
                 TenantItem,
                 %{"name" => "own", "tenant_id" => 1},
                 conflict_target: :name,
                 scope: tenant_one_scope(),
                 repo: TestRepo
               )

      assert count(TenantItem) == 1
    end

    test "upsert update path rolls back an update that moves the row out of scope" do
      insert!(TenantItem, %{name: "mine", tenant_id: 1})

      assert {:error, :scope_violation} =
               Ectomancer.Repo.upsert(
                 TenantItem,
                 %{"name" => "mine", "tenant_id" => 2},
                 conflict_target: :name,
                 scope: tenant_one_scope(),
                 repo: TestRepo
               )

      {:ok, [unchanged]} = Ectomancer.Repo.list(TenantItem, %{"name" => "mine"})
      assert unchanged.tenant_id == 1
    end

    test "upsert update path commits an update that stays in scope" do
      insert!(TenantItem, %{name: "mine", tenant_id: 1})

      assert {:ok, {%{name: "mine", tenant_id: 1, secret: "s2"}, :updated}} =
               Ectomancer.Repo.upsert(
                 TenantItem,
                 %{"name" => "mine", "tenant_id" => 1, "secret" => "s2"},
                 conflict_target: :name,
                 scope: tenant_one_scope(),
                 repo: TestRepo
               )

      {:ok, [row]} = Ectomancer.Repo.list(TenantItem, %{"name" => "mine"})
      assert row.secret == "s2"
    end
  end

  describe "nested transaction semantics" do
    test "a scope violation inside a caller transaction aborts the caller's transaction" do
      result =
        TestRepo.transaction(fn ->
          {:reply, _, _} =
            ScopedTool.CreateTenantItem.execute(%{"name" => "kept", "tenant_id" => 1}, frame(1))

          assert {:error, %Anubis.MCP.Error{message: message}, _} =
                   ScopedTool.CreateTenantItem.execute(
                     %{"name" => "smuggled", "tenant_id" => 2},
                     frame(1)
                   )

          assert message =~ "not found"
          :continued
        end)

      assert {:error, :rollback} = result
      assert count(TenantItem) == 0
    end
  end

  describe "pk-less schemas" do
    test "scoped writes on pk-less schemas fail closed" do
      alias Ectomancer.ScopeWriteEnforcementTest.PkLessMCP.Tool.CreatePkLessItem, as: CreatePkLess

      assert {:error, %Anubis.MCP.Error{message: message}, _} =
               CreatePkLess.execute(%{"name" => "smuggled", "tenant_id" => 2}, frame(1))

      assert message =~ "not found"
      assert count(PkLessItem) == 0
    end
  end
end
