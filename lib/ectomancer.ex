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

        # Expose Ecto schemas as MCP tools
        expose MyApp.Accounts.User,
          actions: [:list, :get, :create, :update]

        # Custom tools with authorization
        tool :admin_stats do
          description "Get admin statistics"
          
          authorize fn actor, _action ->
            actor != nil && actor.role == :admin
          end

          handle fn _params, _actor ->
            {:ok, %{users: 100, revenue: 5000}}
          end
        end

        # Expose Phoenix routes as MCP tools
        expose_routes MyAppWeb.Router
        # Generates: get_users, post_users, get_user, put_user, delete_user, etc.
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

  ## Available Macros

  - `tool/2` - Define custom MCP tools with params and authorization
  - `expose/2` - Auto-generate CRUD tools from Ecto schemas
  - `expose_routes/1` - Auto-generate tools from Phoenix router routes
  - `authorize/1` - Add authorization to tools (use inside tool block)

  ## Authorization

  Ectomancer provides flexible authorization:

  ### Inline Function
      authorize fn actor, action ->
        actor != nil && actor.role == :admin
      end

  ### Policy Module
      authorize with: MyApp.Policies.UserPolicy

  ### Public Access
      authorize :none

  ## Actor Access in Tools

  Tools receive the actor via frame.assigns:

      defmodule MyApp.MCP.MyTool do
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

      import Ectomancer.Tool, only: [tool: 2, authorize: 1]
      import Ectomancer.Expose, only: [expose: 1, expose: 2]
      import Ectomancer.RouteIntrospection, only: [expose_routes: 1, expose_routes: 2]
    end
  end
end
