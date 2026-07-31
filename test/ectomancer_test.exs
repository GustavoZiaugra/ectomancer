defmodule EctomancerTest do
  use ExUnit.Case
  doctest Ectomancer

  test "returns version" do
    assert Ectomancer.version() == Application.spec(:ectomancer, :vsn) |> to_string()
  end

  describe "child_spec/2" do
    test "requires :transports option" do
      assert_raise ArgumentError, ~r/:transports option/, fn ->
        Ectomancer.child_spec(MyApp.MCP, [])
      end
    end

    test "generates spec for a single transport" do
      specs = Ectomancer.child_spec(MyApp.MCP, transports: [:streamable_http])
      assert length(specs) == 1

      {mod, args} = hd(specs)
      assert mod == MyApp.MCP
      assert Keyword.get(args, :transport) == {:streamable_http, start: true}
    end

    test "raises for multiple transports (anubis 1.14 supports one per server)" do
      assert_raise ArgumentError, ~r/single transport per server/, fn ->
        Ectomancer.child_spec(MyApp.MCP, transports: [:streamable_http, :sse])
      end
    end
  end
end
