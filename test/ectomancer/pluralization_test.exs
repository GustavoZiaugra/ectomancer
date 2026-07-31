defmodule Ectomancer.PluralizationTest do
  use ExUnit.Case

  alias Ectomancer.PluralizationTest.TestMCP.Tool.{
    GetAddress,
    GetAnalysis,
    GetBusiness,
    GetClass,
    GetNews,
    GetSeries,
    GetStatus,
    GetUser,
    LegacyGetStatus
  }

  defmodule Status do
    use Ecto.Schema

    schema "statuses" do
      field(:name, :string)
    end
  end

  defmodule Analysis do
    use Ecto.Schema

    schema "analyses" do
      field(:name, :string)
    end
  end

  defmodule Business do
    use Ecto.Schema

    schema "businesses" do
      field(:name, :string)
    end
  end

  defmodule Series do
    use Ecto.Schema

    schema "series" do
      field(:name, :string)
    end
  end

  defmodule Class do
    use Ecto.Schema

    schema "classes" do
      field(:name, :string)
    end
  end

  defmodule Address do
    use Ecto.Schema

    schema "addresses" do
      field(:name, :string)
    end
  end

  defmodule News do
    use Ecto.Schema

    schema "news" do
      field(:name, :string)
    end
  end

  defmodule Users do
    use Ecto.Schema

    schema "users" do
      field(:name, :string)
    end
  end

  defmodule TestMCP do
    use Ectomancer, name: "pluralization-test-mcp", version: "1.0.0"

    expose(Status, actions: [:get])
    expose(Analysis, actions: [:get])
    expose(Business, actions: [:get])
    expose(Series, actions: [:get])
    expose(Class, actions: [:get])
    expose(Address, actions: [:get])
    expose(News, actions: [:get])
    expose(Users, actions: [:get])
    expose(Status, as: :statuses, namespace: :legacy, actions: [:get])
  end

  describe "tool name singularization" do
    test "keeps already-singular words ending in 's' intact" do
      assert GetStatus.name() == "get_status"
      assert GetAnalysis.name() == "get_analysis"
      assert GetBusiness.name() == "get_business"
      assert GetSeries.name() == "get_series"
      assert GetClass.name() == "get_class"
      assert GetAddress.name() == "get_address"
      assert GetNews.name() == "get_news"
    end

    test "singularizes genuine plurals" do
      assert GetUser.name() == "get_user"
    end

    test "singularizes plural resource names from the :as option" do
      assert LegacyGetStatus.name() == "legacy_get_status"
    end
  end
end
