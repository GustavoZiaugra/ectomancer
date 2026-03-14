defmodule Ectomancer do
  @moduledoc """
  Ectomancer - Add an AI brain to your Phoenix app.

  Automatically exposes your Ecto schemas as MCP (Model Context Protocol) tools,
  making your Phoenix app conversationally operable by Claude and other LLMs.

  ## Quick Start

  1. Create your MCP module:

      defmodule MyApp.MCP do
        use Ectomancer,
          name: "my-app-mcp",
          version: "1.0.0"

        # Tools are defined as Anubis.Server.Component.Tool modules
        # See anubis_mcp documentation for details
      end

  2. Add to your router:

      forward "/mcp", Ectomancer.Plug, server: MyApp.MCP

  3. Configure actor extraction:

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

  ## Actor Access in Tools

  Tools receive the actor via frame.assigns:

      defmodule MyApp.MCP.MyTool do
        @behaviour Anubis.Server.Behaviour.Tool

        def execute(params, frame) do
          actor = frame.assigns[:ectomancer_actor]
          # Use actor for authorization...
        end
      end
  """

  @doc """
  Returns the version of Ectomancer.
  """
  def version do
    "0.1.0"
  end

  @doc false
  defmacro __using__(opts) do
    quote do
      use Anubis.Server,
        name: Keyword.get(unquote(opts), :name, "ectomancer-server"),
        version: Keyword.get(unquote(opts), :version, "0.1.0"),
        capabilities: [:tools]

      import Ectomancer.Tool, only: [tool: 2]
      import Ectomancer.Expose, only: [expose: 1, expose: 2]
    end
  end
end
