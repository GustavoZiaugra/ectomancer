if Code.ensure_loaded?(Plug) do
  defmodule Ectomancer.Plug.OAuthProtectedResource do
    @moduledoc """
    Serves the `/.well-known/oauth-protected-resource` discovery document
    (RFC 9728) so OAuth-aware MCP clients — such as claude.ai custom
    connectors — can discover the authorization server for this endpoint.

    ## Configuration

        config :ectomancer, :oauth_protected_resource, %{
          "resource" => "https://your-app.com/mcp",
          "authorization_servers" => [
            "https://auth.your-app.com"
          ],
          "scopes_supported" => ["mcp"]
        }

    ## Router integration

        get "/.well-known/oauth-protected-resource",
            Ectomancer.Plug.OAuthProtectedResource,
            []

    Without configuration the plug returns 404.

    When both this plug and `WWW-Authenticate` challenges are wanted, also set:

        config :ectomancer, :oauth,
          resource_metadata_url: "https://your-app.com/.well-known/oauth-protected-resource"
    """

    @behaviour Plug

    import Plug.Conn

    @impl Plug
    @doc """
    Returns the plug options unchanged.
    """
    @spec init(Plug.opts()) :: Plug.opts()
    def init(opts), do: opts

    @impl Plug
    @doc """
    Sends the configured `:oauth_protected_resource` metadata as JSON with
    status 200, or a JSON 404 when no metadata is configured.
    """
    @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
    def call(conn, _opts) do
      case Application.get_env(:ectomancer, :oauth_protected_resource) do
        metadata when is_map(metadata) ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(metadata))
          |> halt()

        _ ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(404, Jason.encode!(%{error: "Not Found"}))
          |> halt()
      end
    end
  end
else
  defmodule Ectomancer.Plug.OAuthProtectedResource do
    @moduledoc false
  end
end
