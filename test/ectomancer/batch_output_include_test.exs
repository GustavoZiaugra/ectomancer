defmodule Ectomancer.BatchOutputIncludeTest do
  @moduledoc """
  Tests for batch param-key normalization (#145), dynamic include preloading
  (#146), JSON tool output (#147), and batch savepoint isolation (#153).
  """

  use Ectomancer.DataCase

  alias Ectomancer.TestRepo

  defmodule Item do
    use Ecto.Schema

    schema "out_items" do
      field(:name, :string)
      field(:code, :string)

      timestamps()
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "out_comments" do
      field(:body, :string)
      belongs_to(:post, Post)
      timestamps()
    end
  end

  defmodule Post do
    use Ecto.Schema

    schema "out_posts" do
      field(:title, :string)
      has_many(:comments, Comment, foreign_key: :post_id)
      timestamps()
    end
  end

  defmodule ItemMCP do
    use Ectomancer, name: "batch-output-mcp", version: "1.0.0"

    expose(Item, actions: [:list, :get, :create, :batch_create])
  end

  defmodule IncludeMCP do
    use Ectomancer, name: "include-output-mcp", version: "1.0.0"

    expose(Post, as: :post, actions: [:list, :get], preloadable: true)
  end

  @moduletag schemas: [Item, Post, Comment]

  setup %{repo: _repo} do
    Application.put_env(:ectomancer, :repo, TestRepo)

    on_exit(fn ->
      Application.delete_env(:ectomancer, :repo)
    end)

    :ok
  end

  defp execute(tool, params \\ %{}, actor \\ nil) do
    frame = %{assigns: %{ectomancer_actor: actor}}

    case tool.execute(params, frame) do
      {:reply, %Anubis.Server.Response{content: [%{"text" => text}]}, _} -> {:ok, text}
      {:error, error, _} -> {:error, error}
    end
  end

  describe "tool results are JSON" do
    test "list returns valid JSON with no struct noise" do
      insert!(Item, %{name: "Alpha", code: "A1"})
      insert!(Item, %{name: "Beta", code: "B2"})

      assert {:ok, text} = execute(ItemMCP.Tool.ListItems)
      decoded = Jason.decode!(text)

      refute text =~ "__struct__"
      refute text =~ "__meta__"
      refute text =~ "NotLoaded"

      assert is_list(decoded)
      assert Enum.map(decoded, & &1["name"]) |> Enum.sort() == ["Alpha", "Beta"]
    end

    test "list with limit returns paginated JSON" do
      insert!(Item, %{name: "Alpha", code: "A1"})
      insert!(Item, %{name: "Beta", code: "B2"})

      assert {:ok, text} = execute(ItemMCP.Tool.ListItems, %{"limit" => 1})
      decoded = Jason.decode!(text)

      assert %{"data" => data, "pagination" => pagination} = decoded
      assert length(data) == 1
      assert pagination["total"] == 2
      assert pagination["limit"] == 1
    end

    test "get returns a JSON object, not a struct" do
      insert!(Item, %{name: "Alpha", code: "A1"})
      {:ok, [row]} = Ectomancer.Repo.list(Item, %{"name" => "Alpha"})

      assert {:ok, text} = execute(ItemMCP.Tool.GetItem, %{"id" => row.id})
      decoded = Jason.decode!(text)

      assert decoded["name"] == "Alpha"
      assert decoded["code"] == "A1"
    end

    test "create returns a JSON object" do
      assert {:ok, text} = execute(ItemMCP.Tool.CreateItem, %{"name" => "New", "code" => "N1"})
      decoded = Jason.decode!(text)
      assert decoded["name"] == "New"
    end
  end

  describe "batch operations accept atom-keyed params" do
    test "Repo.batch_create with atom records key" do
      assert {:ok, result} =
               Ectomancer.Repo.batch_create(Item, %{records: [%{name: "X", code: "C1"}]})

      assert result.total == 1
      assert length(result.succeeded) == 1
    end

    test "batch_create tool accepts atom-keyed params" do
      assert {:ok, text} =
               execute(ItemMCP.Tool.BatchCreateItems, %{records: [%{name: "Y", code: "C2"}]})

      decoded = Jason.decode!(text)
      assert decoded["total"] == 1
      assert length(decoded["succeeded"]) == 1
    end
  end

  describe "dynamic include preloading" do
    setup do
      insert!(Post, %{title: "Post 1"})
      insert!(Comment, %{body: "Comment 1", post_id: 1})
      insert!(Comment, %{body: "Comment 2", post_id: 1})
      :ok
    end

    test "include: preloads associations in list output" do
      assert {:ok, text} = execute(IncludeMCP.Tool.ListPosts, %{"include" => ["comments"]})
      decoded = Jason.decode!(text)

      assert is_list(decoded)
      assert hd(decoded)["comments"] != nil

      assert Enum.map(hd(decoded)["comments"], & &1["body"]) |> Enum.sort() ==
               ["Comment 1", "Comment 2"]
    end

    test "without include, associations are not leaked" do
      assert {:ok, text} = execute(IncludeMCP.Tool.ListPosts)
      refute text =~ "Comment 1"
    end

    test "disallowed include values are ignored" do
      assert {:ok, text} = execute(IncludeMCP.Tool.ListPosts, %{"include" => ["hack"]})
      decoded = Jason.decode!(text)
      assert is_list(decoded)
    end
  end

  describe "batch savepoints isolate database-level failures" do
    test "a unique violation on one record does not abort the batch" do
      Ectomancer.DataCase.create_unique_index!(Item, :code)
      insert!(Item, %{name: "Existing", code: "DUP"})

      assert {:ok, result} =
               Ectomancer.Repo.batch_create(Item, %{
                 "records" => [
                   %{"name" => "New", "code" => "NEW1"},
                   %{"name" => "Dup", "code" => "DUP"}
                 ]
               })

      assert result.total == 2
      assert length(result.succeeded) == 1
      assert length(result.failed) == 1

      # the surrounding transaction was not poisoned — a follow-up batch works
      assert {:ok, second} =
               Ectomancer.Repo.batch_create(Item, %{
                 "records" => [%{"name" => "Zed", "code" => "Z9"}]
               })

      assert length(second.succeeded) == 1
    end
  end
end
