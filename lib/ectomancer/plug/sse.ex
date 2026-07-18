if Code.ensure_loaded?(Plug) do
  defmodule Ectomancer.Plug.SSE do
    @moduledoc """
    Unified SSE transport wrapper for Ectomancer.

    Wraps `Anubis.Server.Transport.SSE.Plug` to handle both GET (SSE stream)
    and POST (JSON-RPC messages) via a single plug, inspecting `conn.method`
    to delegate to the correct mode.

    ## Deprecation Note

    The underlying SSE transport (`Anubis.Server.Transport.SSE.Plug`) is
    deprecated as of MCP specification 2025-03-26 in favor of Streamable HTTP.
    This module is provided for backward compatibility with clients using the
    2024-11-05 protocol version. For new implementations, use the default
    `:streamable_http` transport.

    ## Router Usage

        get  "/mcp/sse", Ectomancer.Plug, server: MyApp.MCP, transport: :sse
        post "/mcp/sse", Ectomancer.Plug, server: MyApp.MCP, transport: :sse
    """

    @behaviour Plug

    import Plug.Conn

    @deprecated "Use Ectomancer.Plug with :streamable_http transport instead"

    @impl Plug
    def init(opts) do
      sse_state = init_sse_plug(opts, :sse)
      post_state = init_sse_plug(opts, :post)

      %{sse_state: sse_state, post_state: post_state}
    end

    @impl Plug
    def call(conn, %{sse_state: sse_state, post_state: post_state}) do
      case conn.method do
        "GET" ->
          call_sse_plug(conn, sse_state)

        "POST" ->
          call_sse_plug(conn, post_state)

        _ ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(405, Jason.encode!(%{error: "Method not allowed"}))
          |> halt()
      end
    end

    defp init_sse_plug(opts, mode) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Anubis.Server.Transport.SSE.Plug, :init, [Keyword.put(opts, :mode, mode)])
    end

    defp call_sse_plug(conn, state) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Anubis.Server.Transport.SSE.Plug, :call, [conn, state])
    end
  end
end
