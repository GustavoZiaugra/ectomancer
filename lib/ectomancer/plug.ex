defmodule Ectomancer.Plug do
  @moduledoc """
  Phoenix Plug for MCP server integration.

  Provides one-line router integration:

      forward "/mcp", Ectomancer.Plug, server: MyApp.MCP

  This plug:
  1. Extracts the current user (actor) from the connection using the configured `actor_from` function
  2. Injects the actor into connection assigns
  3. Delegates to the Anubis MCP transport layer

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

  ## Options

  - `:server` - The MCP server module (required)
  - `:session_header` - Custom header name for session ID (default: "mcp-session-id")
  - `:request_timeout` - Request timeout in milliseconds (default: 30000)

  The actor will be available in tool handlers via `frame.assigns[:ectomancer_actor]`.
  """

  @behaviour Plug

  import Plug.Conn

  alias Anubis.Server.Transport.StreamableHTTP.Plug, as: AnubisPlug

  @impl Plug
  def init(opts) do
    # Require server option
    _server = Keyword.fetch!(opts, :server)

    # Initialize Anubis plug with our options
    anubis_opts =
      opts
      |> Keyword.put_new(:session_header, "mcp-session-id")
      |> Keyword.put_new(:request_timeout, 30_000)

    anubis_state = AnubisPlug.init(anubis_opts)

    %{
      anubis_state: anubis_state,
      anubis_opts: anubis_opts
    }
  end

  @impl Plug
  def call(conn, %{anubis_state: anubis_state}) do
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
        |> AnubisPlug.call(anubis_state)
    end
  end

  @doc """
  Extracts the actor from the connection using the configured `actor_from` function.

  Returns the actor or `nil` if no actor_from is configured.
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
