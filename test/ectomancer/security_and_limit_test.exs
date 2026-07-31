defmodule Ectomancer.SecurityAndLimitTest do
  @moduledoc """
  Tests for atom-exhaustion hardening (#142) and the configurable limit cap (#150).
  """

  use Ectomancer.DataCase

  alias Ectomancer.Repo
  alias Ectomancer.TestRepo

  defmodule Item do
    use Ecto.Schema

    schema "sec_items" do
      field(:name, :string)
      field(:price, :integer)

      timestamps()
    end
  end

  @moduletag schemas: [Item]

  setup %{repo: _repo} do
    Application.put_env(:ectomancer, :repo, TestRepo)

    on_exit(fn ->
      Application.delete_env(:ectomancer, :repo)
    end)

    :ok
  end

  describe "atom exhaustion hardening (#142)" do
    test "order_by with an unknown value mints no atoms" do
      probe = "ectomancer_probe_#{System.unique_integer([:positive])}"
      insert!(Item, %{name: "A", price: 1})

      assert {:ok, _} = Repo.list(Item, %{"order_by" => probe})
      assert_raise ArgumentError, fn -> String.to_existing_atom(probe) end
    end

    test "order_by with an unknown suffixed value mints no atoms" do
      probe = "ectomancer_probe_gt_#{System.unique_integer([:positive])}"
      insert!(Item, %{name: "A", price: 1})

      assert {:ok, _} = Repo.list(Item, %{"order_by" => probe})
      assert_raise ArgumentError, fn -> String.to_existing_atom(probe) end
    end

    test "filter keys with unknown fields mint no atoms" do
      probe = "ectomancer_fk_#{System.unique_integer([:positive])}"
      insert!(Item, %{name: "A", price: 1})

      assert {:ok, _} = Repo.list(Item, %{probe => "x"})
      assert_raise ArgumentError, fn -> String.to_existing_atom(probe) end
    end

    test "suffixed unknown fields mint no atoms" do
      probe = "ectomancer_fk_gt_#{System.unique_integer([:positive])}"
      insert!(Item, %{name: "A", price: 1})

      assert {:ok, _} = Repo.list(Item, %{probe => 5})
      assert_raise ArgumentError, fn -> String.to_existing_atom(probe) end
    end

    test "valid order_by fields still work" do
      insert!(Item, %{name: "B", price: 2})
      insert!(Item, %{name: "A", price: 1})

      assert {:ok, [%{name: "A"}, %{name: "B"}]} = Repo.list(Item, %{"order_by" => "name"})
    end

    test "unknown attribute values passed to create/update never mint atoms" do
      probe = "ectomancer_attr_#{System.unique_integer([:positive])}"

      assert {:ok, _} = Repo.create(Item, Map.put(%{name: "A"}, probe, "x"))
      assert_raise ArgumentError, fn -> String.to_existing_atom(probe) end
    end
  end

  describe "configurable max limit (#150)" do
    setup do
      for i <- 1..5 do
        insert!(Item, %{name: "Item#{i}", price: i})
      end

      :ok
    end

    test "default cap is 100" do
      Application.delete_env(:ectomancer, :max_limit)

      assert {:ok, %{data: data, pagination: %{limit: 100}}} = Repo.list(Item, %{"limit" => 500})
      assert length(data) == 5
    end

    test "max_limit raises the ceiling" do
      Application.put_env(:ectomancer, :max_limit, 10_000)

      on_exit(fn ->
        Application.delete_env(:ectomancer, :max_limit)
      end)

      assert {:ok, %{data: data, pagination: %{limit: 500}}} = Repo.list(Item, %{"limit" => 500})
      assert length(data) == 5
    end

    test "reports the effective clamped limit" do
      Application.put_env(:ectomancer, :max_limit, 3)

      on_exit(fn ->
        Application.delete_env(:ectomancer, :max_limit)
      end)

      assert {:ok, %{data: data, pagination: %{limit: 3}}} = Repo.list(Item, %{"limit" => 500})
      assert length(data) == 3
    end
  end
end
