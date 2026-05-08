defmodule Ectomancer.PreloadTest do
  use Ectomancer.DataCase,
    schemas: [Ectomancer.PreloadTest.Post, Ectomancer.PreloadTest.Comment]

  alias Ectomancer.Repo
  alias Ectomancer.TestRepo

  defmodule Post do
    use Ecto.Schema

    schema "preload_posts" do
      field(:title, :string)
      field(:body, :string)
      field(:views, :integer)
      has_many(:comments, Ectomancer.PreloadTest.Comment, foreign_key: :post_id)
      timestamps()
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "preload_comments" do
      field(:body, :string)
      belongs_to(:post, Ectomancer.PreloadTest.Post)
      timestamps()
    end
  end

  setup do
    Application.put_env(:ectomancer, :repo, TestRepo)
    Ectomancer.DataCase.create_table_for_schema!(Post)
    Ectomancer.DataCase.create_table_for_schema!(Comment)

    Ectomancer.DataCase.insert!(Post, %{title: "Post 1", body: "Hello", views: 10})
    Ectomancer.DataCase.insert!(Post, %{title: "Post 2", body: "World", views: 20})

    Ectomancer.DataCase.insert!(Comment, %{body: "Comment 1", post_id: 1})
    Ectomancer.DataCase.insert!(Comment, %{body: "Comment 2", post_id: 1})

    on_exit(fn ->
      Application.delete_env(:ectomancer, :repo)
    end)

    :ok
  end

  describe "Repo.get with preload" do
    test "preloads has_many association" do
      {:ok, post} = Repo.get(Post, %{"id" => 1}, preload: [:comments])
      assert length(post.comments) == 2
    end

    test "get without preload returns NotLoaded" do
      {:ok, post} = Repo.get(Post, %{"id" => 1})
      assert match?(%Ecto.Association.NotLoaded{}, post.comments)
    end
  end

  describe "Repo.list with preload" do
    test "preloads on all records" do
      {:ok, posts} = Repo.list(Post, %{}, preload: [:comments])
      assert length(posts) == 2
    end

    test "list without preload" do
      {:ok, posts} = Repo.list(Post, %{})
      assert Enum.all?(posts, &match?(%Ecto.Association.NotLoaded{}, &1.comments))
    end

    test "works with filters" do
      {:ok, posts} = Repo.list(Post, %{"views_gt" => 10}, preload: [:comments])
      assert length(posts) == 1
      assert hd(posts).title == "Post 2"
    end
  end

  describe "expose macro generates tools with preload" do
    test "list tool module is generated" do
      defmodule PreloadTestMCP do
        use Ectomancer

        expose(Ectomancer.PreloadTest.Post,
          actions: [:list, :get],
          preload: [:comments]
        )
      end

      assert {:module, _} = Code.ensure_loaded(PreloadTestMCP.Tool.ListPosts)
      assert {:module, _} = Code.ensure_loaded(PreloadTestMCP.Tool.GetPost)
    end
  end
end
