defmodule Ectomancer.PlugTest do
  use ExUnit.Case

  import Plug.Conn
  import Plug.Test
  alias Ectomancer.Plug

  describe "extract_actor/1" do
    test "returns nil when no actor_from is configured" do
      original_config = Application.get_env(:ectomancer, :actor_from)
      Application.delete_env(:ectomancer, :actor_from)

      conn = conn(:get, "/mcp")
      assert Plug.extract_actor(conn) == nil

      if original_config do
        Application.put_env(:ectomancer, :actor_from, original_config)
      end
    end

    test "extracts actor using configured function" do
      test_actor = %{id: 1, email: "test@example.com"}

      Application.put_env(:ectomancer, :actor_from, fn _conn ->
        test_actor
      end)

      conn = conn(:get, "/mcp")
      assert Plug.extract_actor(conn) == test_actor

      Application.delete_env(:ectomancer, :actor_from)
    end

    test "handles error tuple from actor_from function" do
      Application.put_env(:ectomancer, :actor_from, fn _conn ->
        {:error, :unauthorized}
      end)

      conn = conn(:get, "/mcp")
      assert Plug.extract_actor(conn) == {:error, :unauthorized}

      Application.delete_env(:ectomancer, :actor_from)
    end
  end

  describe "get_actor/1" do
    test "returns actor from conn.assigns" do
      actor = %{id: 1, name: "Test User"}

      conn =
        conn(:get, "/mcp")
        |> assign(:ectomancer_actor, actor)

      assert Plug.get_actor(conn) == actor
    end

    test "returns nil when actor not in assigns" do
      conn = conn(:get, "/mcp")
      assert Plug.get_actor(conn) == nil
    end
  end

  describe "extract_bearer_token/1" do
    test "extracts token from Bearer authorization header" do
      conn =
        conn(:get, "/mcp")
        |> put_req_header("authorization", "Bearer abc123xyz")

      assert Plug.extract_bearer_token(conn) == "abc123xyz"
    end

    test "returns nil for non-Bearer authorization header" do
      conn =
        conn(:get, "/mcp")
        |> put_req_header("authorization", "Basic dXNlcjpwYXNz")

      assert Plug.extract_bearer_token(conn) == nil
    end

    test "returns nil when no authorization header" do
      conn = conn(:get, "/mcp")
      assert Plug.extract_bearer_token(conn) == nil
    end
  end

  describe "extract_api_key/1" do
    test "extracts API key from default header" do
      conn =
        conn(:get, "/mcp")
        |> put_req_header("x-api-key", "secret-key-123")

      assert Plug.extract_api_key(conn) == "secret-key-123"
    end

    test "extracts API key from custom header" do
      conn =
        conn(:get, "/mcp")
        |> put_req_header("x-custom-key", "custom-key-456")

      assert Plug.extract_api_key(conn, "x-custom-key") == "custom-key-456"
    end

    test "returns nil when API key header is missing" do
      conn = conn(:get, "/mcp")
      assert Plug.extract_api_key(conn) == nil
    end
  end

  describe "init/1" do
    test "requires server option" do
      assert_raise KeyError, fn ->
        Plug.init([])
      end
    end

    test "initializes with server option" do
      opts = Plug.init(server: MyApp.MCP)
      assert is_map(opts)
      assert opts.anubis_opts[:server] == MyApp.MCP
    end
  end
end
