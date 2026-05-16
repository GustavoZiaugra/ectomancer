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
  - `expose_oban_jobs/0` - Auto-generate Oban job management tools (requires Oban)
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

  ## Actor Extraction

  Ectomancer extracts the actor (the user/entity making the request) from the Plug
  connection and threads it through the system automatically. Here's how it flows:

  ### 1. Configuration

  Define an `actor_from` function in your config. This function receives the
  `Plug.Conn` struct and returns the actor (or `{:error, reason}` to reject):

      config :ectomancer,
        actor_from: fn conn ->
          case Plug.Conn.get_req_header(conn, "authorization") do
            ["Bearer " <> token] ->
              case MyApp.Auth.verify_token(token) do
                {:ok, user} -> user
                {:error, _} -> {:error, :unauthorized}
              end
            _ ->
              {:error, :unauthorized}
          end
        end

  If no `actor_from` is configured, the actor defaults to `nil` (unauthenticated).

  ### 2. Extraction (Plug layer)

  `Ectomancer.Plug.extract_actor/1` calls your `actor_from` function on every
  incoming request. If the function returns `{:error, reason}`, the request is
  rejected with HTTP 401 before reaching any MCP tools.

  ### 3. Threading (MCP frame)

  The extracted actor is placed into `conn.assigns[:ectomancer_actor]`. Anubis MCP
  propagates this into `frame.assigns[:ectomancer_actor]` for every tool call
  within that session — you never need to re-extract it.

  ### 4. Authorization

  Tool handlers and expose-generated CRUD tools receive the actor automatically:

      # Custom tool
      tool :my_tool do
        authorize fn actor, action -> actor != nil end

        handle fn params, actor, scope ->
          # actor is the user/entity from actor_from
          {:ok, %{message: "Hello, \#{actor.name}"}}
        end
      end

      # Exposed schema (authorization configured separately)
      expose MyApp.User, authorize: fn actor, action ->
        actor.role == :admin
      end

  ### Extraction Flow Summary

  | Layer | Location | What happens |
  |-------|----------|-------------|
  | Config | `config :ectomancer, actor_from: ...` | User provides extraction function |
  | Plug | `Ectomancer.Plug.call/2` | Calls `extract_actor(conn)` |
  | Assigns | `conn.assigns[:ectomancer_actor]` | Actor stored in connection |
  | Frame | `frame.assigns[:ectomancer_actor]` | Anubis propagates to tool context |
  | Tool | `execute(params, frame)` | Actor accessible via `frame.assigns` |
  | Handler | `handle(params, actor, scope)` | Actor passed as 2nd argument |
  | Authorization | `Authorization.check/3` | Actor + action checked against policy |
  """

  @doc """
  Returns the version of Ectomancer.
  """
  def version do
    Application.spec(:ectomancer, :vsn) |> to_string()
  end

  @doc false
  defmacro __using__(opts) do
    quote do
      use Anubis.Server,
        name: Keyword.get(unquote(opts), :name, "ectomancer-server"),
        version: Keyword.get(unquote(opts), :version, "0.1.0"),
        capabilities: [:tools, :resources]

      Module.register_attribute(__MODULE__, :ectomancer_resources, accumulate: true)

      @before_compile Ectomancer

      import Ectomancer.Tool, only: [tool: 2, authorize: 1]
      import Ectomancer.Resource, only: [resource: 2]
      import Ectomancer.Expose, only: [expose: 1, expose: 2]
      import Ectomancer.RouteIntrospection, only: [expose_routes: 1, expose_routes: 2]
      import Ectomancer.ObanBridge, only: [expose_oban_jobs: 0, expose_oban_jobs: 1]
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    resources = Module.get_attribute(env.module, :ectomancer_resources)

    if resources == [] do
      quote do
        :ok
      end
    else
      # The resources attribute accumulates entries in reverse order (LIFO)
      resources = Enum.reverse(resources)

      quote do
        defmodule Resource.Schemas do
          use Anubis.Server.Component,
            type: :resource,
            uri: "ectomancer://schemas",
            name: "schemas",
            mime_type: "application/json"

          @moduledoc "Available Schemas"

          def description, do: "Lists all available schemas in this Ectomancer server"

          def read(_params, frame) do
            schemas_list = unquote(Macro.escape(resources))

            {:reply,
             %Anubis.Server.Response{
               type: :resource,
               content: [
                 %{"type" => "text", "text" => Jason.encode!(%{"schemas" => schemas_list})}
               ]
             }, frame}
          end
        end

        Anubis.Server.component(Resource.Schemas)
      end
    end
  end
end
