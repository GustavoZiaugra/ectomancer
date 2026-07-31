defmodule Ectomancer.ScopeAndRedactionTest do
  @moduledoc """
  Tests for the `scope:` option on `expose` and result-level redaction via
  `only:`/`except:`.
  """

  use Ectomancer.DataCase

  alias Anubis.MCP.Error
  alias Ectomancer.ScopeAndRedactionTest.OnlyMCP.Tool, as: OnlyTool
  alias Ectomancer.ScopeAndRedactionTest.RedactedMCP.Tool, as: RedactedTool
  alias Ectomancer.ScopeAndRedactionTest.ScopedMCP.Tool, as: ScopedTool
  alias Ectomancer.TestRepo

  defmodule TenantItem do
    use Ecto.Schema

    schema "tenant_items" do
      field(:name, :string)
      field(:tenant_id, :integer)
      field(:secret, :string)

      timestamps()
    end
  end

  @moduletag schemas: [TenantItem]

  setup %{repo: _repo} do
    Application.put_env(:ectomancer, :repo, TestRepo)

    on_exit(fn ->
      Application.delete_env(:ectomancer, :repo)
    end)

    :ok
  end

  defmodule ScopedMCP do
    use Ectomancer, name: "scoped-mcp", version: "1.0.0"

    expose(TenantItem,
      actions: [:list, :get, :destroy],
      scope: fn query, actor ->
        import Ecto.Query
        from(t in query, where: t.tenant_id == ^actor.tenant_id)
      end
    )
  end

  defmodule RedactedMCP do
    use Ectomancer, name: "redacted-mcp", version: "1.0.0"

    expose(TenantItem, actions: [:list, :get], except: [:secret])
  end

  defmodule OnlyMCP do
    use Ectomancer, name: "only-mcp", version: "1.0.0"

    expose(TenantItem, actions: [:list], only: [:name])
  end

  defp tool_response_text(tool, params, actor) do
    frame = %{assigns: %{ectomancer_actor: actor}}

    case tool.execute(params, frame) do
      {:reply, %Anubis.Server.Response{content: [%{"text" => text}]}, _} ->
        text

      {:error, error, _} ->
        flunk("Tool execution failed: #{inspect(error)}")
    end
  end

  describe "scope option" do
    setup do
      insert!(TenantItem, %{name: "Tenant 1 A", tenant_id: 1, secret: "s1a"})
      insert!(TenantItem, %{name: "Tenant 1 B", tenant_id: 1, secret: "s1b"})
      insert!(TenantItem, %{name: "Tenant 2 C", tenant_id: 2, secret: "s2c"})
      :ok
    end

    test "list only returns rows matching the actor's scope" do
      text = tool_response_text(ScopedTool.ListTenantItems, %{}, %{tenant_id: 1})

      assert text =~ "Tenant 1 A"
      assert text =~ "Tenant 1 B"
      refute text =~ "Tenant 2 C"
    end

    test "get cannot read a row outside the actor's scope" do
      scoped_text = tool_response_text(ScopedTool.ListTenantItems, %{}, %{tenant_id: 2})
      assert scoped_text =~ "Tenant 2 C"

      {:ok, rows} = Ectomancer.Repo.list(TenantItem, %{"name" => "Tenant 2 C"})
      outside = List.first(rows)

      frame = %{assigns: %{ectomancer_actor: %{tenant_id: 1}}}

      assert {:error, %Error{message: message}, _} =
               ScopedTool.GetTenantItem.execute(%{"id" => outside.id}, frame)

      assert message =~ "not found"
    end

    test "destroy cannot delete a row outside the actor's scope" do
      {:ok, rows} = Ectomancer.Repo.list(TenantItem, %{"name" => "Tenant 2 C"})
      outside = List.first(rows)

      frame = %{assigns: %{ectomancer_actor: %{tenant_id: 1}}}

      assert {:error, %Error{}, _} =
               ScopedTool.DestroyTenantItem.execute(%{"id" => outside.id}, frame)

      {:ok, still_there} = Ectomancer.Repo.list(TenantItem, %{"name" => "Tenant 2 C"})
      assert length(still_there) == 1
    end

    test "scope applies when authorization also returns a policy scope" do
      defmodule PolicyAndConfigScopeMCP do
        use Ectomancer, name: "policy-config-scope", version: "1.0.0"

        expose(TenantItem,
          actions: [:list],
          scope: fn query, actor ->
            import Ecto.Query
            from(t in query, where: t.tenant_id == ^actor.tenant_id)
          end,
          authorize: fn _actor, _action ->
            {:ok, :scoped,
             fn query ->
               import Ecto.Query
               from(t in query, where: t.name != "excluded")
             end}
          end
        )
      end

      insert!(TenantItem, %{name: "excluded", tenant_id: 1, secret: "x"})

      text =
        tool_response_text(PolicyAndConfigScopeMCP.Tool.ListTenantItems, %{}, %{tenant_id: 1})

      assert text =~ "Tenant 1 A"
      refute text =~ "excluded"
    end
  end

  describe "result redaction" do
    setup do
      insert!(TenantItem, %{name: "Public Name", tenant_id: 1, secret: "TOP_SECRET_VALUE"})
      :ok
    end

    test "except: strips excluded fields from list results" do
      text = tool_response_text(RedactedTool.ListTenantItems, %{}, nil)

      assert text =~ "Public Name"
      refute text =~ "TOP_SECRET_VALUE"
    end

    test "except: strips excluded fields from get results" do
      {:ok, [row]} = Ectomancer.Repo.list(TenantItem, %{"name" => "Public Name"})

      text = tool_response_text(RedactedTool.GetTenantItem, %{"id" => row.id}, nil)

      assert text =~ "Public Name"
      refute text =~ "TOP_SECRET_VALUE"
    end

    test "only: restricts results to the whitelist" do
      text = tool_response_text(OnlyTool.ListTenantItems, %{}, nil)

      assert text =~ "Public Name"
      refute text =~ "TOP_SECRET_VALUE"
      refute text =~ "tenant_id"
    end
  end

  describe "Ectomancer.Output.filter_fields/2" do
    test "preserves non-Ecto struct values (datetimes, decimals) when filtering fields" do
      inserted_at = ~N[2026-07-31 10:00:00]
      record = %TenantItem{name: "X", tenant_id: 1, secret: "s", inserted_at: inserted_at}

      filtered = Ectomancer.Output.filter_fields(record, [:name, :inserted_at, :updated_at])

      assert filtered.name == "X"
      assert filtered.inserted_at == inserted_at
      assert Map.has_key?(filtered, :updated_at)
      refute Map.has_key?(filtered, :secret)
      refute Map.has_key?(filtered, :tenant_id)
    end

    test "replaces NotLoaded associations with nil" do
      assert Ectomancer.Output.filter_fields(%Ecto.Association.NotLoaded{}, [:name]) == nil
    end

    test "filters nested records inside maps and lists" do
      record = %TenantItem{name: "X", tenant_id: 1, secret: "s"}

      assert [%{name: "X"}] =
               Ectomancer.Output.filter_fields([record], [:name])

      assert %{items: [%{name: "X"}]} =
               Ectomancer.Output.filter_fields(%{items: [record]}, [:name])
    end
  end

  describe "Ectomancer.Scope.compose/3" do
    test "applies both policy scope and expose scope in order" do
      policy = fn query -> query ++ [:policy] end
      expose = fn query, actor -> query ++ [actor] end

      composed = Ectomancer.Scope.compose(policy, :actor, expose)
      assert composed.([]) == [:policy, :actor]
    end

    test "applies only the expose scope when no policy scope" do
      expose = fn query, actor -> query ++ [actor] end
      composed = Ectomancer.Scope.compose(nil, :actor, expose)
      assert composed.([]) == [:actor]
    end

    test "returns the policy scope when no expose scope" do
      policy = fn query -> query ++ [:policy] end
      assert Ectomancer.Scope.compose(policy, :actor, nil).([]) == [:policy]
    end
  end
end
