defmodule Ectomancer.HasThroughTest do
  @moduledoc """
  Regression test for exposing schemas with `has_many/has_one ... :through`
  associations (#144).
  """

  use ExUnit.Case

  defmodule Comment do
    use Ecto.Schema

    schema "ht_comments" do
      field(:body, :string)
      belongs_to(:post, Post)
      timestamps()
    end
  end

  defmodule Post do
    use Ecto.Schema

    schema "ht_posts" do
      field(:title, :string)
      belongs_to(:author, Author)
      has_many(:comments, Comment)
      timestamps()
    end
  end

  defmodule Author do
    use Ecto.Schema

    schema "ht_authors" do
      field(:name, :string)
      has_many(:posts, Post)
      has_many(:comments, through: [:posts, :comments])
      timestamps()
    end
  end

  test "expose compiles for a schema with a has_through association" do
    defmodule ThroughMCP do
      use Ectomancer, name: "through-mcp", version: "1.0.0"

      expose(Ectomancer.HasThroughTest.Author, actions: [:list, :get])
    end

    assert Code.ensure_loaded?(ThroughMCP.Tool.ListAuthors)
    assert Code.ensure_loaded?(ThroughMCP.Tool.GetAuthor)
  end

  test "get_associations includes the has_through association safely" do
    assocs = Ectomancer.SchemaIntrospection.get_associations(Author)
    names = Enum.map(assocs, & &1.field)

    assert :comments in names
    assert :posts in names
    assert Enum.all?(assocs, & &1.related)
  end
end
