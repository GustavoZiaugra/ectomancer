defmodule Ectomancer.DataCaseTest do
  use Ectomancer.DataCase

  alias Ectomancer.TestRepo

  defmodule CompleteSchema do
    use Ecto.Schema

    schema "complete_schemas" do
      field(:email, :string)
      field(:age, :integer)
      field(:active, :boolean)
      field(:score, :float)
      field(:birth_date, :date)
      field(:wake_time, :time)
      field(:created_at, :naive_datetime)
      field(:published_at, :naive_datetime)
      field(:tags, {:array, :string})
      field(:metadata, :map)
      field(:ref_id, Ecto.UUID)

      timestamps()
    end
  end

  @moduletag schemas: [CompleteSchema]

  setup do
    Ectomancer.DataCase.insert!(CompleteSchema, %{
      email: "a@test.com",
      age: 25,
      active: true,
      score: 3.5,
      birth_date: ~D[1990-01-01],
      wake_time: ~T[07:00:00],
      created_at: ~N[2020-01-01 00:00:00],
      published_at: ~N[2020-01-01 12:00:00],
      tags: ["a", "b"],
      metadata: %{"foo" => "bar"},
      ref_id: "550e8400-e29b-41d4-a716-446655440000"
    })

    Ectomancer.DataCase.insert!(CompleteSchema, %{
      email: "b@test.com",
      age: 30
    })

    :ok
  end

  describe "count/1" do
    test "returns number of records in table" do
      assert Ectomancer.DataCase.count(CompleteSchema) == 2
    end
  end

  describe "create_table_for_schema!/1" do
    test "creates table with all ecto types" do
      # Table should exist and be queryable
      result = TestRepo.query!("SELECT * FROM complete_schemas")
      assert length(result.rows) == 2
    end
  end

  describe "insert!/2" do
    test "auto-populates timestamps when missing" do
      Ectomancer.DataCase.insert!(CompleteSchema, %{email: "c@test.com"})

      assert Ectomancer.DataCase.count(CompleteSchema) == 3
    end
  end
end
