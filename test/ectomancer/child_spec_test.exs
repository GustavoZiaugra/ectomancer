defmodule Ectomancer.ChildSpecTest do
  use ExUnit.Case, async: false

  defmodule TestMCP do
    use Ectomancer, name: "child-spec-test", version: "1.0.0"
  end

  describe "Ectomancer.child_spec/2" do
    test "returns a valid single child spec through the server module" do
      assert {TestMCP, transport: {:streamable_http, start: true}} =
               Ectomancer.child_spec(TestMCP, transports: [:streamable_http])

      # The server module's child_spec/1 (from `use Anubis.Server`) produces the
      # actual start tuple — the tuple form `{MyApp.MCP, transport: ...}` must
      # resolve to start_link/2 on the Anubis supervisor.
      assert %{start: {Anubis.Server.Supervisor, :start_link, [TestMCP, opts]}} =
               TestMCP.child_spec(transport: {:streamable_http, start: true})

      assert Keyword.get(opts, :transport) == {:streamable_http, start: true}
    end

    test "accepts a bare transport atom" do
      assert {TestMCP, transport: {:sse, start: true}} =
               Ectomancer.child_spec(TestMCP, transports: :sse)
    end

    test "boots the transport supervisor under a real supervision tree" do
      pid =
        start_supervised!({TestMCP, transport: {:streamable_http, start: true}})

      assert is_pid(pid)
      assert Process.whereis(:"Anubis.#{TestMCP}.supervisor") != nil
    end

    test "raises when more than one transport is requested" do
      assert_raise ArgumentError, ~r/single transport per server/, fn ->
        Ectomancer.child_spec(TestMCP, transports: [:streamable_http, :sse])
      end
    end

    test "raises for unsupported transports" do
      assert_raise ArgumentError, ~r/Unsupported transport/, fn ->
        Ectomancer.child_spec(TestMCP, transports: [:websocket])
      end
    end

    test "raises when :transports is missing" do
      assert_raise ArgumentError, ~r/:transports option/, fn ->
        Ectomancer.child_spec(TestMCP, [])
      end
    end
  end
end
