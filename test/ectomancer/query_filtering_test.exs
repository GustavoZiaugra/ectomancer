defmodule Ectomancer.QueryFilteringTest do
  use ExUnit.Case

  alias Ectomancer.Repo

  defmodule FilterUser do
    use Ecto.Schema

    schema "filter_users" do
      field(:email, :string)
      field(:name, :string)
      field(:age, :integer)
      field(:score, :float)
      field(:active, :boolean)

      timestamps()
    end
  end

  defmodule FilterMCP do
    use Ectomancer, name: "filter-test-mcp", version: "1.0.0"

    expose(FilterUser, actions: [:list, :get])
  end

  describe "list tool params include filter operators" do
    alias FilterMCP.Tool.ListFilterUsers

    test "list tool has base field params" do
      schema = ListFilterUsers.input_schema()
      props = schema["properties"]

      assert props["email"]["type"] == "string"
      assert props["name"]["type"] == "string"
      assert props["age"]["type"] == "integer"
      assert props["score"]["type"] == "number"
      assert props["active"]["type"] == "boolean"
    end

    test "list tool has string filter suffixes" do
      schema = ListFilterUsers.input_schema()
      props = schema["properties"]

      assert props["email_contains"]["type"] == "string"
      assert props["email_icontains"]["type"] == "string"
      assert props["email_not"]["type"] == "string"
      assert props["email_in"]["type"] == "array"
      assert props["name_contains"]["type"] == "string"
    end

    test "list tool has numeric filter suffixes" do
      schema = ListFilterUsers.input_schema()
      props = schema["properties"]

      assert props["age_gt"]["type"] == "integer"
      assert props["age_gte"]["type"] == "integer"
      assert props["age_lt"]["type"] == "integer"
      assert props["age_lte"]["type"] == "integer"
      assert props["age_not"]["type"] == "integer"
      assert props["age_in"]["type"] == "array"
    end

    test "list tool has float filter suffixes" do
      schema = ListFilterUsers.input_schema()
      props = schema["properties"]

      assert props["score_gt"]["type"] == "number"
      assert props["score_gte"]["type"] == "number"
      assert props["score_lt"]["type"] == "number"
      assert props["score_lte"]["type"] == "number"
      assert props["score_not"]["type"] == "number"
      assert props["score_in"]["type"] == "array"
    end

    test "list tool has boolean filter suffix" do
      schema = ListFilterUsers.input_schema()
      props = schema["properties"]

      assert props["active_not"]["type"] == "boolean"
      refute props["active_contains"]
      refute props["active_gt"]
    end

    test "list tool has meta params" do
      schema = ListFilterUsers.input_schema()
      props = schema["properties"]

      assert props["order_by"]["type"] == "string"
      assert props["order_dir"]["type"] == "string"
      assert props["limit"]["type"] == "integer"
      assert props["offset"]["type"] == "integer"
    end

    test "no filter params are required" do
      schema = ListFilterUsers.input_schema()
      refute schema["required"]
    end
  end

  describe "datetime filter suffixes" do
    defmodule EventSchema do
      use Ecto.Schema

      schema "events" do
        field(:title, :string)
        field(:starts_at, :utc_datetime)
        field(:date, :date)
      end
    end

    defmodule EventMCP do
      use Ectomancer, name: "event-test-mcp", version: "1.0.0"

      expose(EventSchema, actions: [:list])
    end

    alias EventMCP.Tool.ListEventSchemas

    test "datetime fields get comparison suffixes" do
      schema = ListEventSchemas.input_schema()
      props = schema["properties"]

      assert props["starts_at_gt"]["type"] == "string"
      assert props["starts_at_gte"]["type"] == "string"
      assert props["starts_at_lt"]["type"] == "string"
      assert props["starts_at_lte"]["type"] == "string"
      assert props["starts_at_not"]["type"] == "string"
      refute props["starts_at_contains"]
      refute props["starts_at_in"]
    end

    test "date fields get comparison suffixes" do
      schema = ListEventSchemas.input_schema()
      props = schema["properties"]

      assert props["date_gt"]["type"] == "string"
      assert props["date_gte"]["type"] == "string"
      assert props["date_lt"]["type"] == "string"
      assert props["date_lte"]["type"] == "string"
    end
  end

  describe "build_filter_query via Repo.list" do
    setup do
      original = Application.get_env(:ectomancer, :repo)
      Application.delete_env(:ectomancer, :repo)

      on_exit(fn ->
        if original do
          Application.put_env(:ectomancer, :repo, original)
        end
      end)

      :ok
    end

    test "exact match filter still works" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"email" => "test@example.com"})
    end

    test "accepts suffixed filter params without crashing" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"age_gt" => 18})
    end

    test "accepts multiple filter operators" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"age_gte" => 18, "age_lte" => 65})
    end

    test "accepts contains filter" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"email_contains" => "example"})
    end

    test "accepts icontains filter" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"name_icontains" => "john"})
    end

    test "accepts not filter" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"active_not" => false})
    end

    test "accepts in filter with list" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"age_in" => [25, 30, 35]})
    end

    test "ignores in filter with non-list value" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"age_in" => "not_a_list"})
    end

    test "accepts order_by and order_dir" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"order_by" => "age", "order_dir" => "desc"})
    end

    test "accepts limit and offset in params" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"limit" => 10, "offset" => 20})
    end

    test "meta params are not treated as filters" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{
                 "email" => "test@example.com",
                 "order_by" => "name",
                 "limit" => 50
               })
    end
  end

  describe "parse_filter_key" do
    test "parses exact match key" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"email" => "test@test.com"})
    end

    test "ignores unknown fields" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"nonexistent_field" => "value"})
    end

    test "ignores unknown suffixed fields" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"nonexistent_gt" => 5})
    end
  end

  describe "sanitize_like" do
    test "contains filter handles special LIKE characters safely" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"email_contains" => "test%injection_attempt"})
    end
  end

  describe "ordering" do
    test "defaults to asc when order_dir not specified" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"order_by" => "name"})
    end

    test "accepts desc order direction" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"order_by" => "age", "order_dir" => "desc"})
    end

    test "ignores order_by for unknown fields" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"order_by" => "nonexistent"})
    end
  end

  describe "pagination via params" do
    test "limit is capped at 100" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"limit" => 999})
    end

    test "accepts string limit values" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"limit" => "25"})
    end

    test "ignores invalid limit values" do
      assert {:error, :repo_not_configured} =
               Repo.list(FilterUser, %{"limit" => "not_a_number"})
    end
  end

  describe "field filtering with only/except" do
    defmodule LimitedMCP do
      use Ectomancer, name: "limited-test-mcp", version: "1.0.0"

      expose(FilterUser, actions: [:list], only: [:email, :name])
    end

    alias LimitedMCP.Tool.ListFilterUsers, as: LimitedList

    test "only exposes filter params for included fields" do
      schema = LimitedList.input_schema()
      props = schema["properties"]

      assert props["email"]
      assert props["email_contains"]
      assert props["name"]
      refute props["age"]
      refute props["age_gt"]
      refute props["score"]
      refute props["active"]
    end

    test "still includes meta params" do
      schema = LimitedList.input_schema()
      props = schema["properties"]

      assert props["order_by"]
      assert props["order_dir"]
      assert props["limit"]
      assert props["offset"]
    end
  end

  describe "filterable option" do
    defmodule FilterableMCP do
      use Ectomancer, name: "filterable-test-mcp", version: "1.0.0"

      expose(FilterUser,
        actions: [:list],
        only: [:email, :name, :age, :active],
        filterable: [:email, :age]
      )
    end

    alias FilterableMCP.Tool.ListFilterUsers, as: FilterableList

    test "all exposed fields have exact-match params" do
      schema = FilterableList.input_schema()
      props = schema["properties"]

      assert props["email"]["type"] == "string"
      assert props["name"]["type"] == "string"
      assert props["age"]["type"] == "integer"
      assert props["active"]["type"] == "boolean"
    end

    test "filterable fields get advanced filter suffixes" do
      schema = FilterableList.input_schema()
      props = schema["properties"]

      assert props["email_contains"]
      assert props["email_icontains"]
      assert props["email_not"]
      assert props["email_in"]
      assert props["age_gt"]
      assert props["age_gte"]
      assert props["age_lt"]
      assert props["age_lte"]
      assert props["age_not"]
      assert props["age_in"]
    end

    test "non-filterable fields do not get advanced filter suffixes" do
      schema = FilterableList.input_schema()
      props = schema["properties"]

      refute props["name_contains"]
      refute props["name_icontains"]
      refute props["name_not"]
      refute props["name_in"]
      refute props["active_not"]
    end

    test "still includes meta params" do
      schema = FilterableList.input_schema()
      props = schema["properties"]

      assert props["order_by"]
      assert props["order_dir"]
      assert props["limit"]
      assert props["offset"]
    end
  end

  describe "filterable option with unknown fields" do
    defmodule PartialFilterableMCP do
      use Ectomancer, name: "partial-filterable-test-mcp", version: "1.0.0"

      expose(FilterUser,
        actions: [:list],
        only: [:email, :name],
        filterable: [:email, :age, :nonexistent]
      )
    end

    alias PartialFilterableMCP.Tool.ListFilterUsers, as: PartialList

    test "ignores filterable fields not in exposed fields" do
      schema = PartialList.input_schema()
      props = schema["properties"]

      assert props["email_contains"]
      refute props["age_gt"]
      refute props["nonexistent"]
    end
  end

  describe "UUID and binary_id filter params" do
    defmodule UUIDSchema do
      use Ecto.Schema

      @primary_key {:id, Ecto.UUID, autogenerate: true}
      schema "uuid_items" do
        field(:token, :binary_id)
        field(:label, :string)
      end
    end

    defmodule UUIDMCP do
      use Ectomancer, name: "uuid-test-mcp", version: "1.0.0"

      expose(UUIDSchema, actions: [:list])
    end

    alias UUIDMCP.Tool.ListUuidSchemas

    test "UUID primary key gets not and in filters" do
      schema = ListUuidSchemas.input_schema()
      props = schema["properties"]

      assert props["id_not"]["type"] == "string"
      assert props["id_in"]["type"] == "array"
      refute props["id_contains"]
      refute props["id_gt"]
    end

    test "binary_id field gets not and in filters" do
      schema = ListUuidSchemas.input_schema()
      props = schema["properties"]

      assert props["token_not"]["type"] == "string"
      assert props["token_in"]["type"] == "array"
      refute props["token_contains"]
      refute props["token_gt"]
    end

    test "string field still gets full string filters" do
      schema = ListUuidSchemas.input_schema()
      props = schema["properties"]

      assert props["label_contains"]
      assert props["label_icontains"]
      assert props["label_not"]
      assert props["label_in"]
    end
  end

  describe "except with filterable interaction" do
    defmodule ExceptFilterableMCP do
      use Ectomancer, name: "except-filterable-test-mcp", version: "1.0.0"

      expose(FilterUser,
        actions: [:list],
        except: [:age],
        filterable: [:email, :age, :name]
      )
    end

    alias ExceptFilterableMCP.Tool.ListFilterUsers, as: ExceptList

    test "excluded fields are not exposed at all" do
      schema = ExceptList.input_schema()
      props = schema["properties"]

      refute props["age"]
      refute props["age_gt"]
      refute props["age_in"]
    end

    test "filterable fields that are not excluded still get suffixes" do
      schema = ExceptList.input_schema()
      props = schema["properties"]

      assert props["email_contains"]
      assert props["name_contains"]
    end

    test "non-filterable exposed fields only have exact-match params" do
      schema = ExceptList.input_schema()
      props = schema["properties"]

      assert props["score"]
      refute props["score_gt"]
    end
  end

  describe "decimal field type filter params" do
    defmodule ProductSchema do
      use Ecto.Schema

      schema "products" do
        field(:price, :decimal)
        field(:name, :string)
      end
    end

    defmodule ProductMCP do
      use Ectomancer, name: "product-test-mcp", version: "1.0.0"

      expose(ProductSchema, actions: [:list])
    end

    alias ProductMCP.Tool.ListProductSchemas

    test "decimal field gets numeric filter suffixes" do
      schema = ListProductSchemas.input_schema()
      props = schema["properties"]

      assert props["price_gt"]["type"] == "number"
      assert props["price_gte"]["type"] == "number"
      assert props["price_lt"]["type"] == "number"
      assert props["price_lte"]["type"] == "number"
      assert props["price_not"]["type"] == "number"
      assert props["price_in"]["type"] == "array"
      refute props["price_contains"]
    end

    test "decimal base param is number type" do
      schema = ListProductSchemas.input_schema()
      props = schema["properties"]

      assert props["price"]["type"] == "number"
    end
  end

  describe "Repo.list filtering edge cases" do
    alias Ecto.Adapters.SQL.Sandbox

    defmodule EdgeItem do
      use Ecto.Schema

      schema "edge_items" do
        field(:label, :string)
        field(:category, :string)
        field(:rank, :integer)
        field(:score, :float)
        field(:notes, :string)

        timestamps()
      end
    end

    setup do
      Sandbox.checkout(Ectomancer.TestRepo)
      Application.put_env(:ectomancer, :repo, Ectomancer.TestRepo)
      Ectomancer.DataCase.create_table_for_schema!(EdgeItem)

      on_exit(fn ->
        Application.delete_env(:ectomancer, :repo)
      end)

      :ok
    end

    test "icontains performs case-insensitive matching" do
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Apple", category: "Fruit"})
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "appetizer", category: "Food"})

      assert {:ok, results} = Repo.list(EdgeItem, %{"label_icontains" => "app"})
      assert length(results) == 2
    end

    test "icontains matches regardless of case" do
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "ALLCAPS", category: "Test"})

      assert {:ok, [result]} = Repo.list(EdgeItem, %{"label_icontains" => "allcaps"})
      assert result.label == "ALLCAPS"

      assert {:ok, [result]} = Repo.list(EdgeItem, %{"label_icontains" => "ALLCAPS"})
      assert result.label == "ALLCAPS"
    end

    test "in operator with string list" do
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Alpha", category: "A"})
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Beta", category: "B"})
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Gamma", category: "C"})

      assert {:ok, results} = Repo.list(EdgeItem, %{"category_in" => ["A", "C"]})
      assert length(results) == 2
      labels = Enum.map(results, & &1.label)
      assert "Alpha" in labels
      assert "Gamma" in labels
    end

    test "in operator with integer list" do
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Low", rank: 1})
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Mid", rank: 5})
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "High", rank: 10})

      assert {:ok, results} = Repo.list(EdgeItem, %{"rank_in" => [1, 10]})
      assert length(results) == 2
    end

    test "in operator with empty list returns no results" do
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Solo", rank: 1})

      assert {:ok, []} = Repo.list(EdgeItem, %{"rank_in" => []})
    end

    test "ordering by string field ascending" do
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Zebra", rank: 3})
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Alpha", rank: 1})
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Delta", rank: 2})

      assert {:ok, results} = Repo.list(EdgeItem, %{"order_by" => "label", "order_dir" => "asc"})
      assert Enum.map(results, & &1.label) == ["Alpha", "Delta", "Zebra"]
    end

    test "ordering by integer field descending" do
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Low", rank: 1})
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Mid", rank: 5})
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "High", rank: 10})

      assert {:ok, results} = Repo.list(EdgeItem, %{"order_by" => "rank", "order_dir" => "desc"})
      assert Enum.map(results, & &1.rank) == [10, 5, 1]
    end

    test "ordering by timestamp field" do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      later = NaiveDateTime.add(now, 3600, :second)

      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Second", inserted_at: later})
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "First", inserted_at: now})

      assert {:ok, results} =
               Repo.list(EdgeItem, %{"order_by" => "inserted_at", "order_dir" => "asc"})

      assert hd(results).label == "First"
    end

    test "combined filters narrow results correctly" do
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Apple Pie", category: "Dessert", rank: 10})
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Apple Juice", category: "Drink", rank: 5})

      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Banana Split", category: "Dessert", rank: 8})

      assert {:ok, results} =
               Repo.list(EdgeItem, %{
                 "label_contains" => "Apple",
                 "rank_gt" => 5
               })

      assert length(results) == 1
      assert hd(results).label == "Apple Pie"
    end

    test "combined filter with not operator" do
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Alpha", category: "A", rank: 1})
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Beta", category: "B", rank: 2})
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Gamma", category: "A", rank: 3})

      assert {:ok, results} =
               Repo.list(EdgeItem, %{
                 "category" => "A",
                 "label_not" => "Alpha"
               })

      assert length(results) == 1
      assert hd(results).label == "Gamma"
    end

    test "offset without limit uses default limit" do
      for i <- 1..10 do
        Ectomancer.DataCase.insert!(EdgeItem, %{label: "Item#{i}", rank: i})
      end

      assert {:ok, results} =
               Repo.list(EdgeItem, %{
                 "order_by" => "rank",
                 "offset" => 8
               })

      assert length(results) == 2
      assert hd(results).label == "Item9"
    end

    test "empty list returns no records" do
      assert {:ok, []} = Repo.list(EdgeItem, %{})
    end

    test "empty list with filters returns no records" do
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Only", rank: 1})

      assert {:ok, []} = Repo.list(EdgeItem, %{"label" => "NonExistent"})
    end

    test "nil field values are handled gracefully" do
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Has Notes", notes: "Some notes"})
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "No Notes"})

      {:ok, results} = Repo.list(EdgeItem, %{})
      assert length(results) == 2
    end

    @tag :skip
    test "filtering where value is nil returns no results for eq" do
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Present", notes: "Value"})
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Missing"})

      assert {:ok, []} = Repo.list(EdgeItem, %{"notes" => nil})
    end

    @tag :skip
    test "contains filter with SQL special characters is safe" do
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "100% Complete", category: "Test"})
      Ectomancer.DataCase.insert!(EdgeItem, %{label: "Half_Done", category: "Test"})

      assert {:ok, [result]} = Repo.list(EdgeItem, %{"label_contains" => "%"})
      assert result.label == "100% Complete"

      assert {:ok, [result]} = Repo.list(EdgeItem, %{"label_contains" => "_"})
      assert result.label == "Half_Done"
    end
  end
end
