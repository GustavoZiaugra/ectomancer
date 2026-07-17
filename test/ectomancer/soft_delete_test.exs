defmodule Ectomancer.SoftDeleteTest do
  # credo:disable-for-this-file Credo.Check.Design.AliasUsage
  use Ectomancer.DataCase,
    schemas: [
      Ectomancer.SoftDeleteTest.Post,
      Ectomancer.SoftDeleteTest.NoSoftDeletePost
    ]

  alias Ectomancer.Repo
  alias Ectomancer.TestRepo

  defmodule Post do
    use Ecto.Schema

    schema "soft_delete_posts" do
      field(:title, :string)
      field(:body, :string)
      field(:deleted_at, :naive_datetime)
      timestamps()
    end
  end

  defmodule NoSoftDeletePost do
    use Ecto.Schema

    schema "no_soft_delete_posts" do
      field(:title, :string)
      field(:body, :string)
      timestamps()
    end
  end

  setup do
    Application.put_env(:ectomancer, :repo, TestRepo)
    Ectomancer.DataCase.create_table_for_schema!(Post)
    Ectomancer.DataCase.create_table_for_schema!(NoSoftDeletePost)

    Ectomancer.DataCase.insert!(Post, %{title: "Active Post", body: "Hello"})

    Ectomancer.DataCase.insert!(Post, %{
      title: "Deleted Post",
      body: "World",
      deleted_at: ~N[2024-01-01 00:00:00]
    })

    Ectomancer.DataCase.insert!(NoSoftDeletePost, %{title: "Normal Post", body: "Yep"})

    on_exit(fn ->
      Application.delete_env(:ectomancer, :repo)
    end)

    :ok
  end

  describe "SchemaIntrospection.soft_delete_field/1" do
    test "detects deleted_at field" do
      assert Ectomancer.SchemaIntrospection.soft_delete_field(Post) == :deleted_at
    end

    test "returns nil for schema without soft-delete field" do
      assert Ectomancer.SchemaIntrospection.soft_delete_field(NoSoftDeletePost) == nil
    end
  end

  describe "Repo.list with soft-delete" do
    test "filters out soft-deleted records by default" do
      {:ok, posts} = Repo.list(Post, %{})
      assert length(posts) == 1
      assert hd(posts).title == "Active Post"
    end

    test "includes soft-deleted records when include_deleted: true" do
      {:ok, posts} = Repo.list(Post, %{"include_deleted" => true})
      assert length(posts) == 2
    end

    test "works combined with filters" do
      {:ok, posts} = Repo.list(Post, %{"title" => "Deleted"})
      assert posts == []
    end

    test "filters with include_deleted combined" do
      {:ok, posts} = Repo.list(Post, %{"title" => "Deleted Post", "include_deleted" => true})
      assert length(posts) == 1
    end

    test "does not affect schemas without soft-delete" do
      {:ok, posts} = Repo.list(NoSoftDeletePost, %{})
      assert length(posts) == 1
    end
  end

  describe "Repo.get with soft-delete" do
    test "returns active record normally" do
      {:ok, post} = Repo.get(Post, %{"id" => 1})
      assert post.title == "Active Post"
    end

    test "returns not_found for soft-deleted record" do
      assert Repo.get(Post, %{"id" => 2}) == {:error, :not_found}
    end

    test "returns soft-deleted record when include_deleted: true" do
      {:ok, post} = Repo.get(Post, %{"id" => 2, "include_deleted" => true})
      assert post.title == "Deleted Post"
    end

    test "does not affect schemas without soft-delete" do
      {:ok, post} = Repo.get(NoSoftDeletePost, %{"id" => 1})
      assert post.title == "Normal Post"
    end
  end

  describe "Repo.destroy with soft-delete" do
    test "soft-deletes record instead of hard delete" do
      assert {:ok, _deleted_post} = Repo.destroy(Post, %{"id" => 1})

      # Both records are now soft-deleted — list returns none
      {:ok, posts} = Repo.list(Post, %{})
      assert posts == []
    end

    test "still hard-deletes schemas without soft-delete" do
      assert {:ok, _} = Repo.destroy(NoSoftDeletePost, %{"id" => 1})

      {:ok, posts} = Repo.list(NoSoftDeletePost, %{})
      assert posts == []
    end
  end

  describe "Repo.upsert with soft-delete" do
    test "upserting a soft-deleted record restores it" do
      Ectomancer.DataCase.insert!(Post, %{title: "Restore Me", body: "Will be deleted"})

      {:ok, _} = Repo.destroy(Post, %{"id" => 1})

      assert Repo.get(Post, %{"id" => 1}) == {:error, :not_found}

      {:ok, {record, action}} =
        Repo.upsert(Post, %{"title" => "Restore Me", "body" => "Updated body"},
          conflict_target: :title
        )

      assert action == :updated
      assert record.body == "Updated body"
      assert record.deleted_at == nil
    end

    test "upsert inserts new record and sets timestamps" do
      {:ok, {record, action}} =
        Repo.upsert(Post, %{"title" => "Brand New", "body" => "Fresh"}, conflict_target: :title)

      assert action == :inserted
      assert record.title == "Brand New"
      assert record.deleted_at == nil
    end
  end

  describe "Repo.restore" do
    test "restores a soft-deleted record" do
      # Update the record to be soft-deleted directly
      {:ok, record} = Repo.get(Post, %{"id" => 2, "include_deleted" => true})
      sd_field = Ectomancer.SchemaIntrospection.soft_delete_field(Post)
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      changeset = Ecto.Changeset.change(record, %{sd_field => now})
      TestRepo.update!(changeset)

      # Verify it's filtered from list
      {:ok, posts} = Repo.list(Post, %{})
      assert length(posts) == 1

      # Restore
      assert {:ok, restored} = Repo.restore(Post, %{"id" => 2})
      assert restored.deleted_at == nil

      # Now it's back
      {:ok, posts} = Repo.list(Post, %{})
      assert length(posts) == 2
    end

    test "returns not_found for non-existent record" do
      assert Repo.restore(Post, %{"id" => 999}) == {:error, :not_found}
    end

    test "returns not_soft_deletable for schema without soft-delete" do
      assert Repo.restore(NoSoftDeletePost, %{"id" => 1}) == {:error, :not_soft_deletable}
    end
  end

  # Test MCP modules for expose macro tests — defined at top level to avoid compiler warnings
  defmodule SoftDeleteTestMCP do
    use Ectomancer

    expose(Ectomancer.SoftDeleteTest.Post,
      actions: [:list, :get, :destroy],
      soft_delete: true
    )
  end

  defmodule NoSoftDeleteRestoreMCP do
    use Ectomancer

    expose(Ectomancer.SoftDeleteTest.NoSoftDeletePost, actions: [:list, :get])
  end

  defmodule ListWithSoftDeleteMCP do
    use Ectomancer

    expose(Ectomancer.SoftDeleteTest.Post,
      actions: [:list],
      soft_delete: true
    )
  end

  defmodule GetWithSoftDeleteMCP do
    use Ectomancer

    expose(Ectomancer.SoftDeleteTest.Post,
      actions: [:get],
      soft_delete: true
    )
  end

  defmodule ListWithoutSoftDeleteMCP do
    use Ectomancer

    expose(Ectomancer.SoftDeleteTest.NoSoftDeletePost, actions: [:list])
  end

  describe "expose macro generates tools with soft_delete" do
    test "list tool includes include_deleted param" do
      assert {:module, _} = Code.ensure_loaded(SoftDeleteTestMCP.Tool.ListPosts)
      assert {:module, _} = Code.ensure_loaded(SoftDeleteTestMCP.Tool.GetPost)
      assert {:module, _} = Code.ensure_loaded(SoftDeleteTestMCP.Tool.DestroyPost)
    end

    test "generates restore tool" do
      assert {:module, _} = Code.ensure_loaded(SoftDeleteTestMCP.Tool.RestorePost)
    end

    test "does not generate restore without soft_delete" do
      refute Code.ensure_loaded?(NoSoftDeleteRestoreMCP.Tool.RestoreNoSoftDeletePost)
    end

    test "restore tool has correct input params" do
      schema = SoftDeleteTestMCP.Tool.RestorePost.input_schema()
      assert schema["type"] == "object"
      assert schema["properties"]["id"]["type"] == "integer"
      assert "id" in schema["required"]
    end

    test "list tool includes include_deleted in schema when soft_delete enabled" do
      schema = ListWithSoftDeleteMCP.Tool.ListPosts.input_schema()
      assert schema["properties"]["include_deleted"]["type"] == "boolean"
    end

    test "get tool includes include_deleted in schema when soft_delete enabled" do
      schema = GetWithSoftDeleteMCP.Tool.GetPost.input_schema()
      assert schema["properties"]["include_deleted"]["type"] == "boolean"
    end

    test "list tool does not include include_deleted when soft_delete not enabled" do
      schema = ListWithoutSoftDeleteMCP.Tool.ListNoSoftDeletePosts.input_schema()
      refute Map.has_key?(schema["properties"], "include_deleted")
    end
  end
end
