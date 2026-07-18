if Code.ensure_loaded?(Plug) do
  defmodule Ectomancer.Plug do
    @moduledoc """
    Phoenix Plug for MCP server integration.

    Supports multiple transports:

      - `:streamable_http` (default) — MCP Streamable HTTP transport
      - `:sse` — Legacy HTTP+SSE transport (MCP 2024-11-05, deprecated)
      - `:websocket` — WebSocket transport via `Phoenix.Socket.Transport`

    ## Prerequisites

    Before using this plug, you must start the Anubis MCP server in your application.
    The transport backend must match the transport used by the plug.

    ### Streamable HTTP (default)

        # In your application.ex
        children = [
          {Anubis.Server.Supervisor, {MyApp.MCP, transport: {:streamable_http, start: true}}},
          MyAppWeb.Endpoint
        ]

    ### SSE (legacy)

        children = [
          {Anubis.Server.Supervisor, {MyApp.MCP, transport: {:sse, start: true}}},
          MyAppWeb.Endpoint
        ]

    ### Multiple transports

        children = [
          {Anubis.Server.Supervisor, {MyApp.MCP, transport: {:streamable_http, start: true}}},
          {Anubis.Server.Supervisor, {MyApp.MCP, transport: {:sse, start: true}}},
          MyAppWeb.Endpoint
        ]

    See `Ectomancer.child_spec/2` for a helper that generates supervision entries
    for multiple transports.

    ## Router Integration

    ### Streamable HTTP (default)

        scope "/mcp" do
          pipe_through :api
          forward "/", Ectomancer.Plug, server: MyApp.MCP
        end

    ### SSE (legacy)

        scope "/mcp" do
          get  "/sse", Ectomancer.Plug, server: MyApp.MCP, transport: :sse
          post "/sse", Ectomancer.Plug, server: MyApp.MCP, transport: :sse
        end

    ### WebSocket

    WebSocket requires a `Phoenix.Socket.Transport` in your endpoint, not a Plug route.
    Use the `socket` macro instead of `forward`:

        socket "/mcp/ws", Ectomancer.Plug.WebSocket,
          server: MyApp.MCP,
          websocket: [connect_info: [:x_headers, :uri, :peer_data]]

    ## Transport Options

    | Transport | Option Value | Route Method | Backend |
    |-----------|-------------|-------------|---------|
    | Streamable HTTP | `:streamable_http` (default) | `forward` | `Anubis.Server.Transport.StreamableHTTP.Plug` |
    | SSE (legacy) | `:sse` | `get` + `post` | `Anubis.Server.Transport.SSE.Plug` (deprecated) |
    | WebSocket | `:websocket` | `socket` (endpoint) | `Ectomancer.Plug.WebSocket` |

    ## Actor Extraction

    The actor is extracted using the configured `actor_from` function:

        config :ectomancer,
          actor_from: fn conn ->
            conn
            |> Plug.Conn.get_req_header("authorization")
            |> List.first()
            |> case do
              nil -> {:error, :unauthorized}
              "Bearer " <> token -> MyApp.Auth.verify_token(token)
              _ -> {:error, :unauthorized}
            end
          end

    If no `actor_from` is configured, the actor defaults to `nil`.

    ### WebSocket Actor Extraction

    For WebSocket connections, `actor_from` receives a map (not a `Plug.Conn`):

        config :ectomancer,
          actor_from: fn
            %Plug.Conn{} = conn ->
              # HTTP actor extraction
              Ectomancer.Plug.extract_bearer_token(conn) |> verify_token()

            info when is_map(info) ->
              # WebSocket: extract from query params or x_headers
              case info.params["token"] do
                nil -> {:error, :unauthorized}
                token -> verify_token(token)
              end
          end

    ## Options

    - `:server` - The MCP server module (required)
    - `:transport` - Transport type: `:streamable_http`, `:sse`, or `:websocket` (default: `:streamable_http`)
    - `:session_header` - Custom header name for session ID (default: "mcp-session-id", streamable_http only)
    - `:request_timeout` - Request timeout in milliseconds (default: 30000)

    The actor will be available in tool handlers via `frame.assigns[:ectomancer_actor]`.
    """

    @behaviour Plug

    import Plug.Conn

    alias Anubis.Server.Transport.StreamableHTTP.Plug, as: AnubisPlug

    @impl Plug
    def init(opts) do
      transport = Keyword.get(opts, :transport, :streamable_http)
      _server = Keyword.fetch!(opts, :server)

      case transport do
        :streamable_http ->
          anubis_opts =
            opts
            |> Keyword.put_new(:session_header, "mcp-session-id")
            |> Keyword.put_new(:request_timeout, 30_000)

          anubis_state = AnubisPlug.init(anubis_opts)

          %{
            transport: :streamable_http,
            anubis_state: anubis_state,
            anubis_opts: anubis_opts
          }

        :sse ->
          # credo:disable-for-next-line Credo.Check.Refactor.Apply
          sse_state = apply(Ectomancer.Plug.SSE, :init, [opts])

          %{transport: :sse, sse_state: sse_state}

        :websocket ->
          raise ArgumentError,
                "WebSocket transport cannot be used with `forward`. " <>
                  "Use the `socket` macro in your endpoint with Ectomancer.Plug.WebSocket instead. " <>
                  "See Ectomancer.Plug docs for details."
      end
    end

    @doc """
    Handles the MCP request by extracting the actor from the connection and
    delegating to the appropriate transport plug based on the `:transport` option.

    Calls `extract_actor/1` to resolve the actor, then either rejects with
    401 (if `{:error, _}` returned) or stores the actor in
    `conn.assigns[:ectomancer_actor]` and forwards to the transport plug.
    """
    @impl Plug
    def call(conn, state) do
      actor = extract_actor(conn)

      case actor do
        {:error, _reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(401, Jason.encode!(%{error: "Unauthorized"}))
          |> halt()

        _ ->
          conn
          |> assign(:ectomancer_actor, actor)
          |> dispatch_by_transport(state)
      end
    end

    defp dispatch_by_transport(conn, %{transport: :streamable_http, anubis_state: anubis_state}) do
      AnubisPlug.call(conn, anubis_state)
    end

    defp dispatch_by_transport(conn, %{transport: :sse, sse_state: sse_state}) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Ectomancer.Plug.SSE, :call, [conn, sse_state])
    end

    @doc """
    Extracts the actor from the connection using the configured `actor_from` function.

    Reads the application config for `:ectomancer, :actor_from`. If set, calls the
    function with the `conn` and returns its result. If unset, returns `nil`.

    The `actor_from` function can return:
      - Any value — the actor (e.g., a `%User{}` struct, a string, an atom)
      - `{:error, reason}` — the request will be rejected with HTTP 401

    ## Configuration

        config :ectomancer,
          actor_from: fn conn ->
            case Plug.Conn.get_req_header(conn, "authorization") do
              ["Bearer " <> token] -> MyApp.Auth.verify_token(token)
              _ -> {:error, :unauthorized}
            end
          end

    ## Examples

        # With JWT token verification
        config :ectomancer,
          actor_from: fn conn ->
            with ["Bearer " <> token] <- Plug.Conn.get_req_header(conn, "authorization"),
                 {:ok, claims} <- MyApp.JWT.verify(token) do
              MyApp.Accounts.get_user!(claims["sub"])
            else
              _ -> {:error, :unauthorized}
            end
          end

        # With session cookie (read from conn before Plug session)
        config :ectomancer,
          actor_from: fn conn ->
            case Plug.Conn.get_req_header(conn, "cookie") do
              [cookie] -> MyApp.Auth.verify_session(cookie)
              _ -> {:error, :unauthorized}
            end
          end

        # Public API (no auth required)
        # Just omit actor_from — returns nil, tools without authorization pass through

    The extracted actor is stored in `conn.assigns[:ectomancer_actor]` and
    propagated to tool handlers via `frame.assigns[:ectomancer_actor]`.
    """
    @spec extract_actor(Plug.Conn.t()) :: any()
    def extract_actor(conn) do
      case Application.get_env(:ectomancer, :actor_from) do
        nil -> nil
        actor_from when is_function(actor_from, 1) -> actor_from.(conn)
        _ -> nil
      end
    end

    @doc """
    Gets the current actor from the connection assigns.

    ## Examples

        actor = Ectomancer.Plug.get_actor(conn)
    """
    @spec get_actor(Plug.Conn.t()) :: any()
    def get_actor(conn) do
      conn.assigns[:ectomancer_actor]
    end

    @doc """
    Helper function to extract a Bearer token from the Authorization header.

    ## Examples

        token = Ectomancer.Plug.extract_bearer_token(conn)
        # Returns: "abc123" or nil
    """
    @spec extract_bearer_token(Plug.Conn.t()) :: String.t() | nil
    def extract_bearer_token(conn) do
      conn
      |> get_req_header("authorization")
      |> List.first()
      |> case do
        "Bearer " <> token -> token
        _ -> nil
      end
    end

    @doc """
    Helper function to extract API key from a custom header.

    ## Examples

        api_key = Ectomancer.Plug.extract_api_key(conn, "x-api-key")
    """
    @spec extract_api_key(Plug.Conn.t(), String.t()) :: String.t() | nil
    def extract_api_key(conn, header_name \\ "x-api-key") do
      conn
      |> get_req_header(header_name)
      |> List.first()
    end
  end
else
  defmodule Ectomancer.Plug do
    @moduledoc false
  end
end
