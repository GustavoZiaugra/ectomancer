defmodule Ectomancer.PlugIntegrationTest do
  use ExUnit.Case
  import Plug.Conn
  import Plug.Test
  import ExUnit.CaptureLog

  alias Ectomancer.Plug, as: EctomancerPlug
  alias Ectomancer.Plug.WebSocket, as: WSPlug

  defmodule TestAuth do
    def verify_token("valid-token"), do: {:ok, %{id: 1, email: "user@example.com"}}
    def verify_token(_), do: {:error, :invalid_token}
  end

  defmodule TestMCP do
    use Ectomancer,
      name: "test-integration-mcp",
      version: "1.0.0"

    tool :echo do
      description("Echo back the message")
      param(:message, :string, required: true)

      handle(fn %{"message" => msg}, actor ->
        {:ok, %{message: msg, actor_id: actor && actor.id}}
      end)
    end

    tool :system_status do
      description("Get system status information")

      handle(fn _params, _actor ->
        {:ok, %{status: "healthy", version: Ectomancer.version()}}
      end)
    end
  end

  setup do
    original_config = Application.get_env(:ectomancer, :actor_from)

    on_exit(fn ->
      if original_config do
        Application.put_env(:ectomancer, :actor_from, original_config)
      else
        Application.delete_env(:ectomancer, :actor_from)
      end

      :persistent_term.erase({Anubis.Server.Supervisor, TestMCP, :session_config})
    end)

    # Anubis 1.5.0 requires session_config to be set in persistent_term
    # before the plug can be called
    :persistent_term.put(
      {Anubis.Server.Supervisor, TestMCP, :session_config},
      %{
        server_module: TestMCP,
        registry_mod: Anubis.Registry.Swarm,
        transport: [layer: :streamable_http, name: :mcp_test_transport],
        session_idle_timeout: :timer.minutes(30),
        timeout: 30_000,
        task_supervisor: TestMCP.TaskSupervisor,
        task_store: [adapter: Anubis.Server.TaskStore.Default, name: TestMCP.TaskStore]
      }
    )

    :ok
  end

  describe "Plug initialization" do
    test "requires server option" do
      assert_raise KeyError, fn ->
        EctomancerPlug.init([])
      end
    end

    test "initializes with server option (default streamable_http)" do
      opts = EctomancerPlug.init(server: TestMCP)
      assert is_map(opts)
      assert opts.transport == :streamable_http
      assert opts.anubis_opts[:server] == TestMCP
      assert opts.anubis_opts[:session_header] == "mcp-session-id"
      assert opts.anubis_opts[:request_timeout] == 30_000
    end

    test "accepts custom options (streamable_http)" do
      opts =
        EctomancerPlug.init(
          server: TestMCP,
          session_header: "x-custom-session",
          request_timeout: 60_000
        )

      assert opts.anubis_opts[:session_header] == "x-custom-session"
      assert opts.anubis_opts[:request_timeout] == 60_000
    end

    test "initializes with :sse transport" do
      opts = EctomancerPlug.init(server: TestMCP, transport: :sse)
      assert opts.transport == :sse
      assert is_map(opts.sse_state)
    end
  end

  describe "SSE transport" do
    test "init creates correct state" do
      opts = EctomancerPlug.init(server: TestMCP, transport: :sse)
      assert opts.transport == :sse
      assert is_map(opts.sse_state)
    end

    test "rejects non-GET/POST methods via sse wrapper" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      opts = apply(Ectomancer.Plug.SSE, :init, [[server: TestMCP]])

      conn =
        conn(:delete, "/mcp/sse")

      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      result_conn = apply(Ectomancer.Plug.SSE, :call, [conn, opts])

      assert result_conn.status == 405
    end
  end

  describe "Actor extraction" do
    test "returns 401 when actor_from returns error" do
      Application.put_env(:ectomancer, :actor_from, fn _conn ->
        {:error, :unauthorized}
      end)

      opts = EctomancerPlug.init(server: TestMCP)

      conn = conn(:get, "/mcp")
      conn = EctomancerPlug.call(conn, opts)

      assert conn.status == 401
      assert conn.halted == true
    end

    test "allows request when no actor_from configured" do
      Application.delete_env(:ectomancer, :actor_from)

      opts = EctomancerPlug.init(server: TestMCP)

      conn = conn(:get, "/mcp")

      # The plug should not halt when no actor_from is configured
      # It will pass through to Anubis (which may handle it differently)
      result_conn = EctomancerPlug.call(conn, opts)

      # Should have actor set to nil
      assert result_conn.assigns[:ectomancer_actor] == nil
    end

    test "extracts actor from Bearer token" do
      Application.put_env(:ectomancer, :actor_from, fn conn ->
        token = EctomancerPlug.extract_bearer_token(conn)

        case TestAuth.verify_token(token) do
          {:ok, user} -> user
          {:error, _} -> {:error, :unauthorized}
        end
      end)

      opts = EctomancerPlug.init(server: TestMCP)

      conn =
        conn(:get, "/mcp")
        |> put_req_header("authorization", "Bearer valid-token")

      result_conn = EctomancerPlug.call(conn, opts)

      assert result_conn.assigns[:ectomancer_actor] == %{id: 1, email: "user@example.com"}
    end

    test "extracts actor from API key header" do
      Application.put_env(:ectomancer, :actor_from, fn conn ->
        api_key = EctomancerPlug.extract_api_key(conn, "x-api-key")

        if api_key == "secret-key" do
          %{id: 42, role: :admin}
        else
          {:error, :unauthorized}
        end
      end)

      opts = EctomancerPlug.init(server: TestMCP)

      conn =
        conn(:get, "/mcp")
        |> put_req_header("x-api-key", "secret-key")

      result_conn = EctomancerPlug.call(conn, opts)

      assert result_conn.assigns[:ectomancer_actor] == %{id: 42, role: :admin}
    end
  end

  describe "Helper functions" do
    test "extract_bearer_token extracts token from header" do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer abc123")

      assert EctomancerPlug.extract_bearer_token(conn) == "abc123"
    end

    test "extract_bearer_token returns nil for invalid format" do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Basic dXNlcjpwYXNz")

      assert EctomancerPlug.extract_bearer_token(conn) == nil
    end

    test "extract_bearer_token returns nil when header missing" do
      conn = conn(:get, "/")
      assert EctomancerPlug.extract_bearer_token(conn) == nil
    end

    test "extract_api_key extracts from default header" do
      conn =
        conn(:get, "/")
        |> put_req_header("x-api-key", "my-api-key")

      assert EctomancerPlug.extract_api_key(conn) == "my-api-key"
    end

    test "extract_api_key extracts from custom header" do
      conn =
        conn(:get, "/")
        |> put_req_header("x-custom-key", "custom-value")

      assert EctomancerPlug.extract_api_key(conn, "x-custom-key") == "custom-value"
    end

    test "get_actor returns actor from assigns" do
      conn =
        conn(:get, "/")
        |> assign(:ectomancer_actor, %{id: 1})

      assert EctomancerPlug.get_actor(conn) == %{id: 1}
    end

    test "get_actor returns nil when not set" do
      conn = conn(:get, "/")
      assert EctomancerPlug.get_actor(conn) == nil
    end
  end

  describe "Router integration" do
    test "plug works in router pipeline (streamable_http)" do
      defmodule TestRouter do
        use Plug.Router

        plug(:match)
        plug(:dispatch)

        forward("/mcp", to: Ectomancer.Plug, init_opts: [server: TestMCP])
      end

      assert Code.ensure_loaded?(TestRouter)
    end

    test "plug works with sse transport in router" do
      defmodule TestSSERouter do
        use Plug.Router

        plug(:match)
        plug(:dispatch)

        get("/mcp/sse", to: Ectomancer.Plug, init_opts: [server: TestMCP, transport: :sse])
        post("/mcp/sse", to: Ectomancer.Plug, init_opts: [server: TestMCP, transport: :sse])
      end

      assert Code.ensure_loaded?(TestSSERouter)
    end
  end

  describe "WebSocket module" do
    test "module is loaded when Phoenix is available" do
      assert Code.ensure_loaded?(WSPlug)
    end

    test "child_spec returns :ignore" do
      assert WSPlug.child_spec([]) == :ignore
    end

    test "drainer_spec returns :ignore" do
      assert WSPlug.drainer_spec([]) == :ignore
    end

    test "connect with missing server option returns error" do
      ref = make_ref()

      capture_log(fn ->
        result =
          WSPlug.connect(%{
            endpoint: nil,
            transport: :websocket,
            params: %{},
            options: []
          })

        send(self(), {ref, result})
      end)

      assert_receive {^ref, {:error, :missing_server_option}}
    end
  end
end
