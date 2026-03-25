# Ectomancer

> Add an AI brain to your Phoenix app in one afternoon.

**Ectomancer** automatically exposes your Phoenix/Ecto app as an MCP (Model Context Protocol) server, making it conversationally operable by Claude and other LLMs with minimal configuration.

## What it does

Ectomancer sits on top of [anubis_mcp](https://hex.pm/packages/anubis_mcp) and provides three killer features:

1. **Auto-generates MCP tools** from your Ecto schemas — no hand-writing tool definitions
2. **Authorization system** — fine-grained control with inline functions or policy modules
3. **Threads the current user (actor)** through every tool call automatically — auth just works

## Installation

```elixir
def deps do
  [
    {:ectomancer, "~> 0.1.0-rc.3"}
  ]
end
```

## Quick Start

### 1. Create your MCP module

```elixir
defmodule MyApp.MCP do
  use Ectomancer,
    name: "myapp-mcp",
    version: "0.1.0"

  # Expose Ecto schemas as MCP tools
  expose MyApp.Accounts.User,
    actions: [:list, :get, :create, :update]

  # Custom tools with authorization
  tool :send_password_reset do
    description "Send a password reset email to a user"
    param :email, :string, required: true
    
    authorize fn actor, _action ->
      actor != nil  # Must be authenticated
    end

    handle fn %{"email" => email}, actor ->
      MyApp.Accounts.send_reset_email(email, actor)
      {:ok, %{sent: true}}
    end
  end
end
```

### 2. Add to your Application supervisor

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # ... other children ...
      
      # Start Anubis MCP server with your module
      {Anubis.Server.Supervisor, {MyApp.MCP, transport: {:streamable_http, start: true}}},
      
      MyAppWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### 3. Add the route to your router

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/mcp" do
    pipe_through :api
    forward "/", Ectomancer.Plug, server: MyApp.MCP
  end
end
```

### 4. Configure Ectomancer (optional)

```elixir
# config/config.exs
config :ectomancer,
  repo: MyApp.Repo,
  actor_from: fn conn ->
    # Extract current user from conn
    conn.assigns.current_user
  end
```

## Features

### Expose Phoenix Routes (New!)

Auto-discover and expose Phoenix routes as callable MCP tools:

```elixir
defmodule MyApp.MCP do
  use Ectomancer

  # Expose all routes from your router
  expose_routes MyAppWeb.Router
  # Generates: get_users, post_users, get_user, put_user, delete_user, etc.
  
  # Filter specific routes
  expose_routes MyAppWeb.Router, 
    only: ["/api/users", "/api/posts"],
    namespace: :api
  
  # Filter by HTTP methods
  expose_routes MyAppWeb.Router, 
    methods: ["GET", "POST"],
    except: ["/admin"]
end
```

Tool naming:
- `/users` (GET) → `get_users`
- `/users/:id` (GET) → `get_user` (singularized)
- `/users` (POST) → `post_users`
- `/users/:id` (DELETE) → `delete_user`

### Expose Ecto Schemas

Automatically generate CRUD tools from your schemas:

```elixir
# Basic usage - exposes all CRUD actions
expose MyApp.Accounts.User

# Limit actions
expose MyApp.Blog.Post, actions: [:list, :get]

# Read-only mode (disables create, update, destroy)
expose MyApp.Blog.Post, readonly: true

# Filter fields
expose MyApp.Accounts.User, only: [:email, :name]
expose MyApp.Accounts.User, except: [:password_hash]

# Namespace to avoid collisions
expose MyApp.Accounts.User, namespace: :accounts
```

### Custom Tools

Define custom tools with parameters:

```elixir
tool :search_users do
  description "Search users by email"
  param :query, :string, required: true
  param :limit, :integer
  
  handle fn params, _actor ->
    users = MyApp.Accounts.search_users(params["query"], limit: params["limit"])
    {:ok, %{users: users}}
  end
end
```

### Authorization

Ectomancer provides flexible authorization with three strategies:

#### 1. Inline Function

Simple authorization with a function:

```elixir
tool :admin_stats do
  description "Get admin statistics"
  
  authorize fn actor, _action ->
    actor != nil && actor.role == :admin
  end
  
  handle fn _params, _actor ->
    {:ok, %{stats: calculate_stats()}}
  end
end
```

#### 2. Policy Module

Complex authorization with reusable policy modules:

```elixir
defmodule MyApp.Policies.UserPolicy do
  @behaviour Ectomancer.Authorization.Policy
  
  @impl true
  def authorize(actor, action, _opts) do
    case action do
      :list -> :ok  # Public
      :get when actor != nil -> :ok  # Authenticated only
      :create when actor.role == :admin -> :ok  # Admin only
      _ -> {:error, "Unauthorized"}
    end
  end
end

# Use in tool
tool :user_action do
  authorize with: MyApp.Policies.UserPolicy
  # ...
end
```

#### 3. Public Access

No authorization required:

```elixir
tool :public_status do
  description "Get system status"
  authorize :none
  
  handle fn _params, _actor ->
    {:ok, %{status: "operational"}}
  end
end
```

### Schema-Level Authorization

Apply authorization to all actions of a schema:

```elixir
# Global authorization for all actions
expose MyApp.Accounts.User,
  actions: [:list, :get, :create],
  authorize: fn actor, _action -> actor.role == :admin end
```

### Action-Specific Authorization

Fine-grained control per action:

```elixir
expose MyApp.Accounts.User,
  actions: [:list, :get, :create, :update],
  authorize: [
    list: :none,           # Public
    get: fn actor, _ -> actor != nil end,  # Authenticated
    create: :admin_only,    # Admin only
    update: with: MyApp.Policies.UserPolicy  # Policy module
  ]
```

### Error Handling

Ectomancer provides structured error responses for better debugging:

#### Changeset Validation Errors

When `create` or `update` operations fail validation, you get detailed error information:

```elixir
# Example error response
{
  code: -32602,
  message: "Missing required field(s)",
  data: {
    errors: [
      %{field: "Email", message: "can't be blank"},
      %{field: "Name", message: "has invalid format"}
    ],
    count: 2
  }
}
```

Error messages are automatically categorized:
- **presence**: Missing required fields
- **format**: Invalid format (e.g., email regex)
- **inclusion**: Value not in allowed set
- **confirmation**: Confirmation doesn't match
- **length**: String length issues
- **comparison**: Numeric comparison failures

#### Database Errors

Common database errors are mapped to descriptive messages:

- `null value in column` → "Missing required parameter: Field Name"
- `violates foreign key` → "Invalid reference: Related record does not exist"
- `duplicate key` → "Duplicate value: Record with this value already exists"
- `not found` → "Resource not found"

### Binary ID / UUID Support

Ectomancer automatically handles binary_id and UUID primary keys:

```elixir
defmodule MyApp.Accounts.User do
  use Ecto.Schema
  
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    field :email, :string
    # ...
  end
end

# Works seamlessly with expose
expose MyApp.Accounts.User  # get_user, create_user, etc. all work with UUIDs
```

## What Claude gains access to

Once connected, Claude can:

- Query data in natural language ("show me users who signed up this week")
- Run multi-step workflows ("create account, assign plan, send welcome email")
- Give support agents a conversational admin interface
- Serve as a lightweight BI layer over your data
- Inspect queue depth and background workers (with Oban integration)

## Documentation

- [HexDocs](https://hexdocs.pm/ectomancer)
- Full documentation and examples at [GitHub](https://github.com/GustavoZiaugra/ectomancer)

## Testing

Ectomancer includes comprehensive test coverage:

- **189 tests** covering all features
- **35 authorization-specific tests**
- **16 changeset error mapping tests**
- **6 read-only mode tests**
- Full integration tested with Phoenix apps
- Zero compiler warnings
- Full Credo and Dialyzer compliance

Run tests:
```bash
mix test
```

## Status

This project is in active development.

**Phase 3 (Power Features) is complete**, including:
- ✅ Phoenix route introspection via `expose_routes`
- ✅ Auto-generation of tools from Phoenix router routes
- ✅ Smart tool naming with path parameter handling
- ✅ Route filtering and namespace support

**Phase 2 (Authorization) is complete**, including:
- ✅ Authorization system with inline functions, policy modules, and action-specific rules
- ✅ Read-only mode for schemas
- ✅ Ecto changeset error mapping to MCP error responses

Current version: 0.1.0-rc.3

## License

MIT License - see LICENSE file for details.
