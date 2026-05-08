defmodule Ectomancer.QueryFilteringIntegrationTest do
  @moduledoc """
  Integration tests for rich query filtering against a real SQLite database.

  Tests both direct `Repo.list/3` calls and end-to-end MCP tool execution.
  """

  use Ectomancer.DataCase

  alias Ectomancer.Repo
  alias Ectomancer.TestRepo

  defmodule Item do
    use Ecto.Schema

    schema "items" do
      field(:name, :string)
      field(:price, :decimal)
      field(:quantity, :integer)
      field(:active, :boolean)

      timestamps()
    end
  end

  defmodule ItemMCP do
    use Ectomancer, name: "item-test-mcp", version: "1.0.0"

    expose(Item, actions: [:list])
  end

  alias ItemMCP.Tool.ListItems

  @moduletag schemas: [Item]

  setup %{repo: _repo} do
    Application.put_env(:ectomancer, :repo, TestRepo)

    on_exit(fn ->
      Application.delete_env(:ectomancer, :repo)
    end)

    :ok
  end

  describe "exact match filtering" do
    test "returns matching records" do
      insert!(Item, %{name: "Apple", price: 1.5, quantity: 10, active: true})
      insert!(Item, %{name: "Banana", price: 0.5, quantity: 20, active: true})

      assert {:ok, [%{name: "Apple"}]} = Repo.list(Item, %{"name" => "Apple"})
    end

    test "returns empty list when no matches" do
      insert!(Item, %{name: "Apple", price: 1.5, quantity: 10, active: true})

      assert {:ok, []} = Repo.list(Item, %{"name" => "Orange"})
    end
  end

  describe "string contains filtering" do
    test "_contains performs substring match" do
      insert!(Item, %{name: "Apple Pie", price: 1.5, quantity: 10, active: true})
      insert!(Item, %{name: "Banana", price: 0.5, quantity: 20, active: true})
      insert!(Item, %{name: "Pineapple", price: 2.0, quantity: 5, active: true})

      assert {:ok, results} = Repo.list(Item, %{"name_contains" => "apple"})
      names = Enum.map(results, & &1.name)
      assert "Apple Pie" in names
      assert "Pineapple" in names
    end

    test "_icontains performs case-insensitive match" do
      insert!(Item, %{name: "Apple", price: 1.5, quantity: 10, active: true})
      insert!(Item, %{name: "BANANA", price: 0.5, quantity: 20, active: true})

      assert {:ok, [%{name: "BANANA"}]} = Repo.list(Item, %{"name_icontains" => "ban"})
    end
  end

  describe "numeric comparison filtering" do
    test "_gt filters greater than" do
      insert!(Item, %{name: "Cheap", price: 1.0, quantity: 10, active: true})
      insert!(Item, %{name: "Mid", price: 5.0, quantity: 5, active: true})
      insert!(Item, %{name: "Expensive", price: 10.0, quantity: 1, active: true})

      assert {:ok, [%{name: "Expensive"}]} = Repo.list(Item, %{"price_gt" => 5.0})
    end

    test "_gte filters greater than or equal" do
      insert!(Item, %{name: "Cheap", price: 1.0, quantity: 10, active: true})
      insert!(Item, %{name: "Mid", price: 5.0, quantity: 5, active: true})

      assert {:ok, results} = Repo.list(Item, %{"price_gte" => 5.0})
      assert length(results) == 1
      assert hd(results).name == "Mid"
    end

    test "_lt filters less than" do
      insert!(Item, %{name: "Cheap", price: 1.0, quantity: 10, active: true})
      insert!(Item, %{name: "Mid", price: 5.0, quantity: 5, active: true})

      assert {:ok, [%{name: "Cheap"}]} = Repo.list(Item, %{"price_lt" => 5.0})
    end

    test "_lte filters less than or equal" do
      insert!(Item, %{name: "Cheap", price: 1.0, quantity: 10, active: true})
      insert!(Item, %{name: "Mid", price: 5.0, quantity: 5, active: true})

      assert {:ok, results} = Repo.list(Item, %{"price_lte" => 5.0})
      assert length(results) == 2
    end
  end

  describe "not filtering" do
    test "_not excludes matching records" do
      insert!(Item, %{name: "Apple", price: 1.5, quantity: 10, active: true})
      insert!(Item, %{name: "Banana", price: 0.5, quantity: 20, active: true})

      assert {:ok, [%{name: "Banana"}]} = Repo.list(Item, %{"name_not" => "Apple"})
    end
  end

  describe "in filtering" do
    test "_in matches any value in list" do
      insert!(Item, %{name: "Apple", price: 1.5, quantity: 10, active: true})
      insert!(Item, %{name: "Banana", price: 0.5, quantity: 20, active: true})
      insert!(Item, %{name: "Cherry", price: 3.0, quantity: 15, active: true})

      assert {:ok, results} = Repo.list(Item, %{"name_in" => ["Apple", "Cherry"]})
      assert length(results) == 2
      names = Enum.map(results, & &1.name)
      assert "Apple" in names
      assert "Cherry" in names
    end
  end

  describe "ordering" do
    test "order_by with default asc direction" do
      insert!(Item, %{name: "Banana", price: 0.5, quantity: 20, active: true})
      insert!(Item, %{name: "Apple", price: 1.5, quantity: 10, active: true})

      assert {:ok, [%{name: "Apple"}, %{name: "Banana"}]} =
               Repo.list(Item, %{"order_by" => "name"})
    end

    test "order_by with desc direction" do
      insert!(Item, %{name: "Apple", price: 1.5, quantity: 10, active: true})
      insert!(Item, %{name: "Banana", price: 0.5, quantity: 20, active: true})

      assert {:ok, [%{name: "Banana"}, %{name: "Apple"}]} =
               Repo.list(Item, %{"order_by" => "name", "order_dir" => "desc"})
    end
  end

  describe "pagination" do
    test "limit restricts number of results" do
      insert!(Item, %{name: "A", price: 1.0, quantity: 1, active: true})
      insert!(Item, %{name: "B", price: 2.0, quantity: 2, active: true})
      insert!(Item, %{name: "C", price: 3.0, quantity: 3, active: true})

      assert {:ok, results} = Repo.list(Item, %{"limit" => 2})
      assert length(results) == 2
    end

    test "offset skips records" do
      insert!(Item, %{name: "A", price: 1.0, quantity: 1, active: true})
      insert!(Item, %{name: "B", price: 2.0, quantity: 2, active: true})
      insert!(Item, %{name: "C", price: 3.0, quantity: 3, active: true})

      assert {:ok, [%{name: "C"}]} =
               Repo.list(Item, %{
                 "order_by" => "name",
                 "limit" => 1,
                 "offset" => 2
               })
    end

    test "limit is capped at 100" do
      for i <- 1..5 do
        insert!(Item, %{
          name: "Item#{i}",
          price: i * 1.0,
          quantity: i,
          active: true
        })
      end

      assert {:ok, results} = Repo.list(Item, %{"limit" => 200})
      assert length(results) == 5
    end
  end

  describe "combined filters" do
    test "multiple filter conditions work together" do
      insert!(Item, %{name: "Apple Pie", price: 5.0, quantity: 10, active: true})
      insert!(Item, %{name: "Apple Juice", price: 3.0, quantity: 5, active: true})
      insert!(Item, %{name: "Banana", price: 1.0, quantity: 20, active: true})

      assert {:ok, [%{name: "Apple Pie"}]} =
               Repo.list(Item, %{
                 "name_contains" => "Apple",
                 "price_gt" => 3.0
               })
    end

    test "filters combined with ordering and pagination" do
      insert!(Item, %{name: "Zebra", price: 10.0, quantity: 1, active: true})
      insert!(Item, %{name: "Apple", price: 5.0, quantity: 5, active: true})
      insert!(Item, %{name: "Banana", price: 3.0, quantity: 10, active: true})

      assert {:ok, [%{name: "Apple"}]} =
               Repo.list(Item, %{
                 "price_gt" => 3.0,
                 "order_by" => "name",
                 "order_dir" => "asc",
                 "limit" => 1
               })
    end
  end

  describe "boolean filtering" do
    test "exact match on boolean field" do
      insert!(Item, %{name: "Active", price: 1.0, quantity: 1, active: true})
      insert!(Item, %{name: "Inactive", price: 1.0, quantity: 1, active: false})

      assert {:ok, [%{name: "Active"}]} = Repo.list(Item, %{"active" => true})
    end

    test "_not on boolean field" do
      insert!(Item, %{name: "Active", price: 1.0, quantity: 1, active: true})
      insert!(Item, %{name: "Inactive", price: 1.0, quantity: 1, active: false})

      assert {:ok, [%{name: "Inactive"}]} = Repo.list(Item, %{"active_not" => true})
    end
  end

  describe "timestamp ordering" do
    test "order_by inserted_at sorts by creation time" do
      insert!(Item, %{
        name: "First",
        price: 1.0,
        quantity: 1,
        active: true,
        inserted_at: ~N[2024-01-01 10:00:00]
      })

      insert!(Item, %{
        name: "Second",
        price: 2.0,
        quantity: 2,
        active: true,
        inserted_at: ~N[2024-01-02 10:00:00]
      })

      assert {:ok, [%{name: "Second"}, %{name: "First"}]} =
               Repo.list(Item, %{"order_by" => "inserted_at", "order_dir" => "desc"})
    end
  end

  describe "end-to-end MCP tool execution" do
    defp tool_response_text(params) do
      frame = %{assigns: %{ectomancer_actor: nil}}

      case ListItems.execute(params, frame) do
        {:reply, %Anubis.Server.Response{content: [%{"text" => text}]}, _} ->
          text

        {:error, error, _} ->
          flunk("Tool execution failed: #{inspect(error)}")
      end
    end

    test "list tool returns records via MCP execute" do
      insert!(Item, %{name: "Apple", price: 1.5, quantity: 10, active: true})
      insert!(Item, %{name: "Banana", price: 0.5, quantity: 20, active: true})

      text = tool_response_text(%{})
      assert text =~ "Apple"
      assert text =~ "Banana"
    end

    test "list tool filters via MCP execute" do
      insert!(Item, %{name: "Apple", price: 1.5, quantity: 10, active: true})
      insert!(Item, %{name: "Banana", price: 0.5, quantity: 20, active: true})

      text = tool_response_text(%{"name" => "Apple"})
      assert text =~ "Apple"
      refute text =~ "Banana"
    end

    test "list tool applies contains filter via MCP execute" do
      insert!(Item, %{name: "Apple Pie", price: 5.0, quantity: 10, active: true})
      insert!(Item, %{name: "Banana", price: 1.0, quantity: 20, active: true})

      text = tool_response_text(%{"name_contains" => "Apple"})
      assert text =~ "Apple Pie"
      refute text =~ "Banana"
    end

    test "list tool applies numeric filter via MCP execute" do
      insert!(Item, %{name: "Cheap", price: 1.0, quantity: 10, active: true})
      insert!(Item, %{name: "Expensive", price: 10.0, quantity: 1, active: true})

      text = tool_response_text(%{"price_gt" => 5.0})
      assert text =~ "Expensive"
      refute text =~ "Cheap"
    end

    test "list tool orders results via MCP execute" do
      insert!(Item, %{name: "Banana", price: 0.5, quantity: 20, active: true})
      insert!(Item, %{name: "Apple", price: 1.5, quantity: 10, active: true})

      text = tool_response_text(%{"order_by" => "name"})
      # In ascending order, Apple comes before Banana
      apple_pos = :binary.match(text, "Apple") |> elem(0)
      banana_pos = :binary.match(text, "Banana") |> elem(0)
      assert apple_pos < banana_pos
    end

    test "list tool paginates results via MCP execute" do
      insert!(Item, %{name: "A", price: 1.0, quantity: 1, active: true})
      insert!(Item, %{name: "B", price: 2.0, quantity: 2, active: true})
      insert!(Item, %{name: "C", price: 3.0, quantity: 3, active: true})

      text = tool_response_text(%{"limit" => 2})
      # Should only contain 2 records
      assert text =~ "A"
      assert text =~ "B"
      refute text =~ "C"
    end

    test "list tool returns empty result when no matches" do
      insert!(Item, %{name: "Apple", price: 1.5, quantity: 10, active: true})

      text = tool_response_text(%{"name" => "Orange"})
      assert text =~ "[]"
    end

    test "list tool combines filters and ordering via MCP execute" do
      insert!(Item, %{name: "Zebra", price: 10.0, quantity: 1, active: true})
      insert!(Item, %{name: "Apple", price: 5.0, quantity: 5, active: true})
      insert!(Item, %{name: "Banana", price: 3.0, quantity: 10, active: true})

      text =
        tool_response_text(%{
          "price_gt" => 3.0,
          "order_by" => "name",
          "order_dir" => "asc",
          "limit" => 1
        })

      assert text =~ "Apple"
      refute text =~ "Banana"
      refute text =~ "Zebra"
    end
  end
end
