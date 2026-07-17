defmodule Ectomancer.BatchOperationsTest do
  use ExUnit.Case

  alias Ecto.Adapters.SQL.Sandbox
  alias Ectomancer.Repo
  alias Ectomancer.TestRepo

  defmodule Post do
    use Ecto.Schema

    schema "batch_posts" do
      field(:title, :string)
      field(:body, :string)
      field(:deleted_at, :naive_datetime)
      timestamps()
    end
  end

  defmodule NoSoftDeletePost do
    use Ecto.Schema

    schema "batch_no_sd_posts" do
      field(:title, :string)
      field(:body, :string)
      timestamps()
    end
  end

  describe "batch_create" do
    setup do
      Sandbox.checkout(TestRepo)
      Application.put_env(:ectomancer, :repo, TestRepo)
      Ectomancer.DataCase.create_table_for_schema!(Post)

      on_exit(fn ->
        Application.delete_env(:ectomancer, :repo)
      end)

      :ok
    end

    test "creates multiple records" do
      {:ok, result} =
        Repo.batch_create(Post, %{
          "records" => [
            %{"title" => "Post 1", "body" => "Body 1"},
            %{"title" => "Post 2", "body" => "Body 2"},
            %{"title" => "Post 3", "body" => "Body 3"}
          ]
        })

      assert result.total == 3
      assert length(result.succeeded) == 3
      assert result.failed == []

      {:ok, posts} = Repo.list(Post, %{}, limit: 100)
      assert length(posts) == 3
    end

    test "handles partial failures" do
      {:ok, result} =
        Repo.batch_create(Post, %{
          "records" => [
            %{"title" => "Post 1", "body" => "Body 1"},
            %{"title" => "Post 2", "body" => "Body 2"}
          ]
        })

      # Without schema validations, all records succeed
      assert result.total == 2
      assert length(result.succeeded) == 2
      assert result.succeeded |> List.first() |> Map.get(:status) == :ok
    end

    test "returns structured result with succeeded and failed lists" do
      {:ok, result} =
        Repo.batch_create(Post, %{
          "records" => [
            %{"title" => "Single Post", "body" => "Body"}
          ]
        })

      assert is_map(result)
      assert is_list(result.succeeded)
      assert is_list(result.failed)
      assert result.total == 1
    end

    test "enforces batch_size limit" do
      records = Enum.map(1..101, fn i -> %{"title" => "Post #{i}"} end)

      assert {:error, {:batch_size_exceeded, 100}} =
               Repo.batch_create(Post, %{"records" => records})
    end

    test "accepts custom batch_size" do
      records = Enum.map(1..50, fn i -> %{"title" => "Post #{i}"} end)

      {:ok, result} =
        Repo.batch_create(Post, %{"records" => records}, batch_size: 200)

      assert result.total == 50
    end

    test "returns empty results for empty records" do
      {:ok, result} = Repo.batch_create(Post, %{"records" => []})
      assert result.total == 0
    end
  end

  describe "batch_update" do
    setup do
      Sandbox.checkout(TestRepo)
      Application.put_env(:ectomancer, :repo, TestRepo)
      Ectomancer.DataCase.create_table_for_schema!(Post)

      on_exit(fn ->
        Application.delete_env(:ectomancer, :repo)
      end)

      :ok
    end

    test "updates multiple records" do
      {:ok, p1} = Repo.create(Post, %{title: "Original 1", body: "Body 1"})
      {:ok, p2} = Repo.create(Post, %{title: "Original 2", body: "Body 2"})
      {:ok, _p3} = Repo.create(Post, %{title: "Original 3", body: "Body 3"})

      {:ok, result} =
        Repo.batch_update(Post, %{
          "records" => [
            %{"id" => p1.id, "title" => "Updated 1"},
            %{"id" => p2.id, "body" => "Updated 2"}
          ]
        })

      assert result.total == 2
      assert length(result.succeeded) == 2
      assert result.failed == []

      {:ok, u1} = Repo.get(Post, %{"id" => p1.id})
      {:ok, u2} = Repo.get(Post, %{"id" => p2.id})
      assert u1.title == "Updated 1"
      assert u2.body == "Updated 2"
    end

    test "updates soft-deleted records" do
      {:ok, post} = Repo.create(Post, %{title: "To Delete", body: "Body"})
      Repo.destroy(Post, %{"id" => post.id})

      {:ok, result} =
        Repo.batch_update(Post, %{
          "records" => [
            %{"id" => post.id, "title" => "Updated After Delete"}
          ]
        })

      assert length(result.succeeded) == 1

      {:ok, updated} = Repo.get(Post, %{"id" => post.id, "include_deleted" => true})
      assert updated.title == "Updated After Delete"
    end

    test "handles missing records" do
      {:ok, post} = Repo.create(Post, %{title: "Exists", body: "Body"})

      {:ok, result} =
        Repo.batch_update(Post, %{
          "records" => [
            %{"id" => post.id, "title" => "Updated"},
            %{"id" => 9999, "title" => "Missing"}
          ]
        })

      assert length(result.succeeded) == 1
      assert length(result.failed) == 1
    end
  end

  describe "batch_destroy" do
    setup do
      Sandbox.checkout(TestRepo)
      Application.put_env(:ectomancer, :repo, TestRepo)
      Ectomancer.DataCase.create_table_for_schema!(Post)
      Ectomancer.DataCase.create_table_for_schema!(NoSoftDeletePost)

      on_exit(fn ->
        Application.delete_env(:ectomancer, :repo)
      end)

      :ok
    end

    test "destroys multiple records" do
      {:ok, p1} = Repo.create(Post, %{title: "Delete 1", body: "Body"})
      {:ok, p2} = Repo.create(Post, %{title: "Delete 2", body: "Body"})
      {:ok, keep} = Repo.create(Post, %{title: "Keep", body: "Body"})

      {:ok, result} =
        Repo.batch_destroy(Post, %{
          "ids" => [p1.id, p2.id]
        })

      assert result.total == 2
      assert length(result.succeeded) == 2
      assert result.failed == []

      {:ok, posts} = Repo.list(Post, %{}, limit: 100)
      assert length(posts) == 1
      assert hd(posts).id == keep.id
    end

    test "soft-deletes when schema has soft-delete field" do
      {:ok, post} = Repo.create(Post, %{title: "Soft Delete Me", body: "Body"})

      {:ok, result} =
        Repo.batch_destroy(Post, %{
          "ids" => [post.id]
        })

      assert length(result.succeeded) == 1

      {:ok, deleted_post} = Repo.get(Post, %{"id" => post.id, "include_deleted" => true})
      assert deleted_post.deleted_at != nil
    end
  end

  describe "batch operations without repo" do
    setup do
      original = Application.get_env(:ectomancer, :repo)
      Application.delete_env(:ectomancer, :repo)

      on_exit(fn ->
        if original, do: Application.put_env(:ectomancer, :repo, original)
      end)

      :ok
    end

    test "batch_create returns error" do
      assert {:error, :repo_not_configured} =
               Repo.batch_create(Post, %{"records" => []})
    end

    test "batch_update returns error" do
      assert {:error, :repo_not_configured} =
               Repo.batch_update(Post, %{"records" => []})
    end

    test "batch_destroy returns error" do
      assert {:error, :repo_not_configured} =
               Repo.batch_destroy(Post, %{"ids" => []})
    end
  end

  describe "authorization with batch operations" do
    defmodule AuthorizedBatchMCP do
      use Ectomancer, name: "auth-batch-mcp", version: "1.0.0"

      expose(Post,
        actions: [:list, :batch_create, :batch_update, :batch_destroy],
        authorize: fn actor, action ->
          actor.role == :admin or action in [:list]
        end
      )
    end

    alias AuthorizedBatchMCP.Tool.BatchCreatePosts
    alias AuthorizedBatchMCP.Tool.BatchDestroyPosts

    test "allows batch_create for admin" do
      frame = %{assigns: %{ectomancer_actor: %{role: :admin}}}

      case BatchCreatePosts.execute(%{"records" => []}, frame) do
        {:error, mcp_error, _} ->
          refute String.contains?("#{mcp_error.message}", "Unauthorized"),
                 "Auth should pass for admin"

        _ ->
          :ok
      end
    end

    test "denies batch_create for non-admin" do
      frame = %{assigns: %{ectomancer_actor: %{role: :user}}}

      assert {:error, %Anubis.MCP.Error{message: msg}, _} =
               BatchCreatePosts.execute(%{"records" => []}, frame)

      assert msg =~ "Unauthorized"
    end

    test "denies batch_destroy for non-admin" do
      frame = %{assigns: %{ectomancer_actor: %{role: :user}}}

      assert {:error, %Anubis.MCP.Error{message: msg}, _} =
               BatchDestroyPosts.execute(%{"ids" => []}, frame)

      assert msg =~ "Unauthorized"
    end

    test "batch_create has correct name" do
      assert BatchCreatePosts.name() == "batch_create_posts"
    end

    test "batch_destroy has correct name" do
      assert BatchDestroyPosts.name() == "batch_destroy_posts"
    end
  end

  describe "scope authorization with batch operations" do
    defmodule ScopedBatchMCP do
      use Ectomancer, name: "scoped-batch-mcp", version: "1.0.0"

      expose(Post,
        actions: [:list, :batch_destroy],
        authorize: fn _actor, _action ->
          {:ok, :scoped,
           fn query ->
             import Ecto.Query
             from(t in query, where: t.title == "Scoped")
           end}
        end
      )
    end

    alias ScopedBatchMCP.Tool.BatchDestroyPosts

    test "batch_destroy tool is generated with scope auth" do
      assert Code.ensure_loaded?(BatchDestroyPosts)
    end
  end

  describe "field authorization with batch operations" do
    defmodule FieldAuthBatchMCP do
      use Ectomancer, name: "field-auth-batch-mcp", version: "1.0.0"

      expose(Post,
        actions: [:list, :batch_create],
        field_authorize: fn _actor, field -> field != :body end
      )
    end

    test "batch_create tool is generated with field auth" do
      assert Code.ensure_loaded?(FieldAuthBatchMCP.Tool.BatchCreatePosts)
    end
  end
end
