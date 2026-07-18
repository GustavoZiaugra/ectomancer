defmodule EctomancerTest do
  use ExUnit.Case
  doctest Ectomancer

  test "returns version" do
    assert Ectomancer.version() == Application.spec(:ectomancer, :vsn) |> to_string()
  end

  describe "child_spec/2" do
    test "requires :transports option" do
      assert_raise KeyError, fn ->
        Ectomancer.child_spec(MyApp.MCP, [])
      end
    end

    test "generates spec for a single transport" do
      specs = Ectomancer.child_spec(MyApp.MCP, transports: [:streamable_http])
      assert length(specs) == 1

      {mod, args} = hd(specs)
      assert mod == Anubis.Server.Supervisor
      assert elem(args, 1)[:transport] == {:streamable_http, start: true}
    end

    test "generates specs for multiple transports" do
      specs = Ectomancer.child_spec(MyApp.MCP, transports: [:streamable_http, :sse])
      assert length(specs) == 2

      [first, second] = specs

      assert {Anubis.Server.Supervisor, {MyApp.MCP, [transport: {:streamable_http, start: true}]}} =
               first

      assert {Anubis.Server.Supervisor, {MyApp.MCP, [transport: {:sse, start: true}]}} = second
    end
  end
end
