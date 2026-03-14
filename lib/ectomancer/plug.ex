defmodule Ectomancer.Plug do
  @moduledoc """
  Phoenix Plug for MCP server integration.

  Provides one-line router integration:

      forward "/mcp", Ectomancer.Plug

  This plug:
  1. Extracts the current user (actor) from the connection
  2. Injects the actor into connection assigns
  3. Delegates to the MCP transport layer
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    # NOTE: Implement actor extraction and MCP transport
    conn
  end
end
