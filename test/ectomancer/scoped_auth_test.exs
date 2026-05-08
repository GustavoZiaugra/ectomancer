defmodule Ectomancer.ScopedAuthTest do
  use Ectomancer.DataCase,
    schemas: [Ectomancer.ScopedAuthTest.Task]

  alias Ectomancer.Repo
  alias Ectomancer.TestRepo

  defmodule Task do
    use Ecto.Schema

    schema "scoped_tasks" do
      field(:title, :string)
      field(:user_id, :integer)
      timestamps()
    end
  end

  defmodule TaskMCP do
    use Ectomancer, name: "scoped-test", version: "1.0.0"

    expose(Task,
      actions: [:list, :get, :create, :update, :destroy],
      authorize: fn actor, action ->
        cond do
          # Admin sees everything
          actor.role == :admin ->
            :ok

          # Regular users only see their own tasks
          action in [:list, :get] ->
            {:ok, :scoped,
             fn query ->
               import Ecto.Query
               from(t in query, where: t.user_id == ^actor.id)
             end}

          # Regular users can only update/destroy their own tasks
          action in [:update, :destroy] ->
            {:ok, :scoped,
             fn query ->
               import Ecto.Query
               from(t in query, where: t.user_id == ^actor.id)
             end}

          # Create — no scope needed, just check auth
          action == :create ->
            :ok

          true ->
            {:error, "Unknown action"}
        end
      end
    )
  end

  setup do
    Application.put_env(:ectomancer, :repo, TestRepo)
    Ectomancer.DataCase.create_table_for_schema!(Task)

    # Insert tasks for user 1 and user 2
    Ectomancer.DataCase.insert!(Task, %{title: "User 1 Task A", user_id: 1})
    Ectomancer.DataCase.insert!(Task, %{title: "User 1 Task B", user_id: 1})
    Ectomancer.DataCase.insert!(Task, %{title: "User 2 Task A", user_id: 2})
    Ectomancer.DataCase.insert!(Task, %{title: "Admin Task", user_id: 0})

    on_exit(fn ->
      Application.delete_env(:ectomancer, :repo)
    end)

    :ok
  end

  describe "Repo.list with scoped auth" do
    test "user 1 only sees their own tasks" do
      {:ok, tasks} =
        Repo.list(Task, %{},
          scope: fn query ->
            import Ecto.Query
            from(t in query, where: t.user_id == ^1)
          end
        )

      assert length(tasks) == 2
      assert Enum.all?(tasks, &(&1.user_id == 1))
    end

    test "user 2 only sees their own tasks" do
      {:ok, tasks} =
        Repo.list(Task, %{},
          scope: fn query ->
            import Ecto.Query
            from(t in query, where: t.user_id == ^2)
          end
        )

      assert length(tasks) == 1
      assert hd(tasks).user_id == 2
    end

    test "nil scope returns all tasks" do
      {:ok, tasks} = Repo.list(Task, %{}, scope: nil)
      assert length(tasks) == 4
    end

    test "scope composes with filters" do
      {:ok, tasks} =
        Repo.list(Task, %{"title" => "User 1 Task A"},
          scope: fn query ->
            import Ecto.Query
            from(t in query, where: t.user_id == ^1)
          end
        )

      assert length(tasks) == 1
      assert hd(tasks).title == "User 1 Task A"
    end
  end

  describe "Repo.get with scoped auth" do
    test "user can only get their own record" do
      # User 1 can get their own task
      assert {:ok, _} =
               Repo.get(Task, %{"id" => 1},
                 scope: fn query ->
                   import Ecto.Query
                   from(t in query, where: t.user_id == ^1)
                 end
               )

      # User 1 cannot get user 2's task
      assert Repo.get(Task, %{"id" => 3},
               scope: fn query ->
                 import Ecto.Query
                 from(t in query, where: t.user_id == ^1)
               end
             ) == {:error, :not_found}
    end
  end

  describe "Repo.update with scoped auth" do
    test "user can only update their own record" do
      # User 1 can update their own task
      assert {:ok, updated} =
               Repo.update(Task, %{"id" => 1, "title" => "Updated"},
                 scope: fn query ->
                   import Ecto.Query
                   from(t in query, where: t.user_id == ^1)
                 end
               )

      assert updated.title == "Updated"

      # User 1 cannot update user 2's task
      assert Repo.update(Task, %{"id" => 3, "title" => "Hacked"},
               scope: fn query ->
                 import Ecto.Query
                 from(t in query, where: t.user_id == ^1)
               end
             ) == {:error, :not_found}
    end
  end

  describe "Repo.destroy with scoped auth" do
    test "user can only destroy their own record" do
      # User 1 can destroy their own task
      assert {:ok, _} =
               Repo.destroy(Task, %{"id" => 1},
                 scope: fn query ->
                   import Ecto.Query
                   from(t in query, where: t.user_id == ^1)
                 end
               )

      # User 1 cannot destroy user 2's task
      assert Repo.destroy(Task, %{"id" => 3},
               scope: fn query ->
                 import Ecto.Query
                 from(t in query, where: t.user_id == ^1)
               end
             ) == {:error, :not_found}
    end
  end

  describe "expose macro generates scoped auth handlers" do
    test "list tool module exists" do
      assert {:module, _} = Code.ensure_loaded(TaskMCP.Tool.ListTasks)
    end

    test "get tool module exists" do
      assert {:module, _} = Code.ensure_loaded(TaskMCP.Tool.GetTask)
    end

    test "all expected tools exist" do
      assert {:module, _} = Code.ensure_loaded(TaskMCP.Tool.ListTasks)
      assert {:module, _} = Code.ensure_loaded(TaskMCP.Tool.GetTask)
      assert {:module, _} = Code.ensure_loaded(TaskMCP.Tool.CreateTask)
      assert {:module, _} = Code.ensure_loaded(TaskMCP.Tool.UpdateTask)
      assert {:module, _} = Code.ensure_loaded(TaskMCP.Tool.DestroyTask)
    end
  end

  describe "authorization inline function with scoped" do
    test "inline auth handler returns scoped result" do
      handler = fn actor, :list ->
        {:ok, :scoped,
         fn query ->
           import Ecto.Query
           from(t in query, where: t.user_id == ^actor.id)
         end}
      end

      actor = %{id: 1}
      result = Ectomancer.Authorization.check(actor, :list, handler: handler)

      assert match?({:ok, :scoped, _}, result)
    end
  end
end
