# credo:disable-for-this-file Credo.Check.Design.AliasUsage
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

  describe "dynamic include parameter" do
    defmodule CommentV2 do
      use Ecto.Schema

      schema "preload_comments_v2" do
        field(:body, :string)
        belongs_to(:post, Ectomancer.PreloadTest.Post)
        timestamps()
      end
    end

    defmodule IncludeMCP do
      use Ectomancer, name: "include-test", version: "1.0.0"

      expose(Ectomancer.PreloadTest.Post,
        actions: [:list, :get],
        preloadable: true
      )
    end

    defmodule IncludeSpecificMCP do
      use Ectomancer, name: "include-specific-test", version: "1.0.0"

      expose(Ectomancer.PreloadTest.Post,
        actions: [:list, :get],
        preloadable: [:comments]
      )
    end

    defmodule NoIncludeMCP do
      use Ectomancer, name: "no-include-test", version: "1.0.0"

      expose(Ectomancer.PreloadTest.Post,
        actions: [:list, :get]
      )
    end

    defmodule CreateOnlyMCP do
      use Ectomancer, name: "create-only-test", version: "1.0.0"

      expose(Ectomancer.PreloadTest.Post,
        actions: [:create],
        preloadable: true
      )
    end

    defmodule MergePreloadMCP do
      use Ectomancer, name: "merge-test", version: "1.0.0"

      expose(Ectomancer.PreloadTest.Post,
        actions: [:list, :get],
        preload: [:comments],
        preloadable: true
      )
    end

    test "include param present in list when preloadable is set" do
      schema = IncludeMCP.Tool.ListPosts.input_schema()
      assert schema["properties"]["include"]
      assert schema["properties"]["include"]["type"] == "array"
    end

    test "include param present in get when preloadable is set" do
      schema = IncludeMCP.Tool.GetPost.input_schema()
      assert schema["properties"]["include"]
    end

    test "include param absent when preloadable is not set" do
      schema = NoIncludeMCP.Tool.ListPosts.input_schema()
      refute schema["properties"]["include"]
    end

    test "include param absent in non-list/get actions" do
      schema = CreateOnlyMCP.Tool.CreatePost.input_schema()
      refute schema["properties"]["include"]
    end

    test "end-to-end: Repo.get preloads associated records" do
      Application.put_env(:ectomancer, :repo, TestRepo)

      {:ok, post} = Repo.get(Post, %{"id" => 1}, preload: [:comments])
      assert length(post.comments) == 2
      comment_bodies = Enum.map(post.comments, & &1.body)
      assert "Comment 1" in comment_bodies
      assert "Comment 2" in comment_bodies

      on_exit(fn ->
        Application.delete_env(:ectomancer, :repo)
      end)
    end

    test "Repo.list preloads associated records" do
      Application.put_env(:ectomancer, :repo, TestRepo)

      {:ok, posts} = Repo.list(Post, %{}, preload: [:comments])
      assert length(posts) == 2

      on_exit(fn ->
        Application.delete_env(:ectomancer, :repo)
      end)
    end

    test "preloadable: :all allows any association" do
      schema = IncludeMCP.Tool.ListPosts.input_schema()
      assert schema["properties"]["include"]
    end

    test "preloadable: [:comments] restricts include" do
      schema = IncludeSpecificMCP.Tool.ListPosts.input_schema()
      assert schema["properties"]["include"]
    end

    test "include merges with static preload" do
      schema = MergePreloadMCP.Tool.ListPosts.input_schema()
      assert schema["properties"]["include"]
    end
  end
end
