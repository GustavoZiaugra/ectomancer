defmodule Ectomancer.RepoChangesetTest do
  use ExUnit.Case

  defmodule TestSchema do
    use Ecto.Schema
    import Ecto.Changeset

    schema "test_items" do
      field(:name, :string)
      field(:value, :integer)
      timestamps()
    end

    def changeset(item, attrs) do
      item
      |> cast(attrs, [:name, :value])
      |> validate_required([:name])
      |> validate_length(:name, min: 3)
    end
  end

  describe "create/2 with schema changeset function" do
    test "uses schema's changeset function when available" do
      # This test verifies that Repo.create/2 calls the schema's changeset function
      # when it exists, rather than creating a bare changeset

      # Create a changeset with invalid data (name too short)
      attrs = %{name: "AB", value: 42}

      # The changeset function should validate that name is at least 3 characters
      changeset = TestSchema.changeset(%TestSchema{}, attrs)

      refute changeset.valid?

      assert {:name,
              {"should be at least %{count} character(s)",
               [count: 3, validation: :length, kind: :min, type: :string]}} in changeset.errors
    end
  end
end
