# Ectomancer

[![CI](https://github.com/GustavoZiaugra/ectomancer/workflows/CI/badge.svg)](https://github.com/GustavoZiaugra/ectomancer/actions?query=workflow%3ACI)
[![Hex.pm](https://img.shields.io/hexpm/v/ectomancer)](https://hex.pm/packages/ectomancer)
[![Hex Docs](https://img.shields.io/badge/docs-hexpm-blue)](https://hexdocs.pm/ectomancer)
[![Downloads](https://img.shields.io/hexpm/dt/ectomancer)](https://hex.pm/packages/ectomancer)
[![License](https://img.shields.io/hexpm/l/ectomancer)](https://github.com/GustavoZiaugra/ectomancer/blob/main/LICENSE)

**Auto-generate MCP tools from your Ecto schemas — your Phoenix app, now conversationally operable by Claude and any LLM.**

Ectomancer sits on top of [anubis_mcp](https://hex.pm/packages/anubis_mcp) and turns your database schemas into live MCP tools. Add it to your router, start the server, and your AI assistant can query, create, and update records through natural language — no hand-written tool definitions, no boilerplate.

## Features

- **Schema → MCP tools** — auto-generates CRUD tools from `expose MyApp.Accounts.User`
- **Route introspection** — `expose_routes MyAppWeb.Router` turns HTTP endpoints into callable tools
- **Authorization system** — inline functions, policy modules, or action-specific rules
- **Actor threading** — the current user flows through every tool call automatically
- **Custom tools** — `tool :search_users do ... end` with typed params
- **Upsert operations** — `upsert_{resource}` for insert-or-update workflows with conflict target and `on_conflict` control
- **Batch operations** — `batch_create`, `batch_update`, `batch_destroy` for transactional multi-record operations
- **Custom resources** — `resource :system_status do ... end` with URI templates, MIME types, and authorization
- **MCP Prompts** — `prompt :analyze_churn do ... end` for structured, parameterized prompt templates with argument validation
- **Rate limiting** — configurable token bucket per tool or globally
- **Multi-repo support** — expose schemas from different repos simultaneously
- **MCP Resources** — schemas auto-register at `ectomancer://schemas/{name}`, plus custom resources with URI templates, MIME types, and read handlers
- **Browser playground** — zero-dep HTML client at `priv/ectomancer.html`, no build step
- **Oban integration** — optional bridge for inspecting queue depth and workers
- **Interactive installer** — `mix ectomancer.setup` auto-discovers schemas and patches your project
- **Igniter installer** — `mix igniter.install ectomancer` auto-configures Ectomancer with schema selection, config files, router routes, and supervision tree

## Demo

Watch Ectomancer in action — a full Phoenix app with User, Post, and Comment schemas exposed as MCP tools, running on the Streamable HTTP transport.

![Ectomancer Demo](priv/demo.gif)

*3 Ecto schemas → 15 MCP tools with zero boilerplate. Replay locally with `asciinema play priv/demo.cast`.*

The demo shows:
- **3 Ecto schemas** → **15+ MCP tools** (list, get, create, update, destroy + batch operations) with zero boilerplate
- **Advanced filtering** — `list_posts(title_contains: "MCP")` with automatic LIKE operators
- **Association support** — create posts linked to users through MCP tool calls
- **Real-time interaction** — query, create, and update records conversationally

Try it yourself:

```bash
git clone https://github.com/GustavoZiaugra/ectomancer_demo
cd ectomancer_demo
mix setup
mix phx.server
# Connect your MCP client to http://localhost:4000/mcp
```

## Installation

Add `ectomancer` to your dependencies:

```elixir
def deps do
  [
    {:ectomancer, "~> 1.6"}
  ]
end
```

Then run one of the installers:

### Option A: Igniter installer (recommended)

```bash
mix igniter.install ectomancer
```

This automatically:
1. Adds the `ectomancer` dependency
2. Checks for required dependencies (Ecto, Plug)
3. Discovers Ecto schemas in your project and prompts you to select which to expose
4. Generates an MCP module (`lib/my_app/mcp.ex`) with the selected schemas
5. Configures Ectomancer in `config/config.exs`
6. Adds the MCP route to your Phoenix router
7. Adds the Anubis supervisor to your application supervision tree

### Option B: Interactive setup

```bash
mix ectomancer.setup
```

An interactive wizard that does the same as above but runs as a standalone Mix task.

### Option C: Manual setup

```elixir
defmodule MyApp.MCP do
  use Ectomancer,
    name: "myapp-mcp",
    version: "0.1.0",
    authorize: with: MyApp.Policies.GlobalPolicy

  expose MyApp.Accounts.User,
    actions: [:list, :get, :create, :update]

  expose MyApp.Blog.Post,
    actions: [:list, :get]

  tool :search_users do
    description "Search users by email"
    param :query, :string, required: true
    param :limit, :integer

    handle fn %{"query" => q, "limit" => l}, _actor ->
      {:ok, MyApp.Accounts.search_users(q, limit: l || 10)}
    end
  end

  resource :system_status do
    description "Current system health metrics"
    uri "metrics://status"
    mime_type "application/json"

    read fn _params, _actor ->
      {:ok, Jason.encode!(%{status: "healthy", uptime: System.uptime()})}
    end
  end

  prompt :analyze_churn do
    description "Analyze user churn over a time period"
    argument :days, :integer, required: true, description: "Days to look back"
    argument :threshold, :float, default: 0.05, description: "Churn threshold"

    messages fn args ->
      [
        %{
          role: :user,
          content: %{
            type: :text,
            text: "Using the list_users and get_user tools, analyze churn over the last #{args["days"]} days with threshold #{args["threshold"]}."
          }
        }
      ]
    end
  end
end
```

Then start the MCP server by adding to your Application supervisor:

```elixir
children = [
  # ... other children ...
  {Anubis.Server.Supervisor, {MyApp.MCP, transport: {:streamable_http, start: true}}},
  MyAppWeb.Endpoint
]
```

And mount in your router:

```elixir
scope "/mcp" do
  pipe_through :api
  forward "/", Ectomancer.Plug, server: MyApp.MCP
end
```

Finally, configure actor extraction:

```elixir
config :ectomancer,
  repo: MyApp.Repo,
  actor_from: fn conn ->
    conn.assigns.current_user
  end
```

Done. Claude can now query your database through natural language at `/mcp`.

## Transports

Ectomancer supports three transport options. Streamable HTTP is the default and recommended transport.

### Transport Comparison

| Feature | Streamable HTTP | SSE (legacy) | WebSocket |
|---------|----------------|-------------|-----------|
| MCP protocol | 2025-03-26+ | 2024-11-05 | Any version |
| Status | **Recommended** | Deprecated | Available |
| Endpoints | Single (`forward`) | Dual (GET + POST) | Phoenix socket |
| Server notifications | Yes (SSE streaming) | Yes | Stub (future) |
| Router method | `forward` | `get` + `post` | `socket` in endpoint |
| Actor extraction | Plug.Conn | Plug.Conn | map (see below) |

### Streamable HTTP (default)

```elixir
# Supervision
{Anubis.Server.Supervisor, {MyApp.MCP, transport: {:streamable_http, start: true}}}

# Router
forward "/mcp", Ectomancer.Plug, server: MyApp.MCP
```

### SSE (legacy, deprecated)

For clients that only support the MCP 2024-11-05 HTTP+SSE protocol:

```elixir
# Supervision
{Anubis.Server.Supervisor, {MyApp.MCP, transport: {:sse, start: true}}}

# Router
get  "/mcp/sse", Ectomancer.Plug, server: MyApp.MCP, transport: :sse
post "/mcp/sse", Ectomancer.Plug, server: MyApp.MCP, transport: :sse
```

### WebSocket

For bidirectional communication via WebSocket. Requires Phoenix's `socket` macro in your endpoint:

```elixir
# In lib/my_app/endpoint.ex
socket "/mcp/ws", Ectomancer.Plug.WebSocket,
  server: MyApp.MCP,
  websocket: [connect_info: [:x_headers, :uri, :peer_data]]
```

The server module is resolved from application config (not from socket-level options,
which Phoenix does not pass to transport callbacks):

```elixir
# In config/config.exs
config :ectomancer, :ws_server, MyApp.MCP
```

WebSocket actor extraction receives a map instead of a `Plug.Conn`:

```elixir
config :ectomancer,
  actor_from: fn
    %Plug.Conn{} = conn ->
      # HTTP: standard Plug.Conn extraction
      Ectomancer.Plug.extract_bearer_token(conn) |> MyApp.Auth.verify_token()

    info when is_map(info) ->
      # WebSocket: extract from query params or x_headers
      case info.params["token"] do
        nil ->
          headers = info.connect_info[:x_headers] || []
          {_, header_token} = List.keyfind(headers, "authorization", 0, {nil, nil})
          String.replace_prefix(header_token || "", "Bearer ", "")
          |> MyApp.Auth.verify_token()
        token ->
          MyApp.Auth.verify_token(token)
      end
  end
```

### Multiple Transports

Start multiple transport backends to serve different clients:

```elixir
children = [
  Ectomancer.child_spec(MyApp.MCP, transports: [:streamable_http, :sse]),
  MyAppWeb.Endpoint
]
```

Then mount each transport in your router as shown above.

## Authorization

Three strategies, choose what fits:

| Style | Example | Use case |
|-------|---------|----------|
| **Inline** | `authorize fn actor, _ -> actor.role == :admin end` | Quick rules |
| **Policy module** | `authorize with: MyApp.Policies.UserPolicy` | Complex logic, reusable |
| **None** | `authorize :none` | Public endpoints |

### Global authorization

Set a policy for the entire server — it cascades to all schemas, custom tools, and route introspection tools:

```elixir
use Ectomancer,
  name: "myapp-mcp",
  authorize: fn actor, _ -> actor.role == :admin end
```

You can also use a policy module:

```elixir
use Ectomancer,
  name: "myapp-mcp",
  authorize: with: MyApp.Policies.GlobalPolicy
```

Per-schema `authorize` overrides the global policy for that schema. Action-specific rules override further. Both must pass when both are set (cascading).

### Per-schema and per-action rules

Schema-level and action-specific rules work too:

```elixir
expose MyApp.Accounts.User,
  actions: [:list, :get, :create, :update],
  authorize: [
    list: :none,
    get: fn actor, _ -> actor != nil end,
    create: :admin_only,
    update: with: MyApp.Policies.UserPolicy
  ]
```

Oban tools support the same per-action patterns:

```elixir
expose_oban_jobs authorize: [
  all: fn actor, _ -> actor.role == :admin end,
  list_queues: :none
]
```

## Configuration

### Sources

```elixir
config :ectomancer, repo: MyApp.Repo
```

### Actor extraction

```elixir
config :ectomancer,
  actor_from: fn conn ->
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> MyApp.Auth.verify_token(token)
      _ -> {:error, :unauthorized}
    end
  end
```

### Rate limiting

```elixir
config :ectomancer, :rate_limits,
  enabled: true,
  global: [max_requests: 100, time_window_ms: 60_000],
  per_tool: [search_users: [max_requests: 10, time_window_ms: 60_000]]
```

### Telemetry

Ectomancer emits `:telemetry` events for monitoring, observability, and debugging.
Events are enabled by default. Disable by setting `telemetry: false`:

```elixir
config :ectomancer, telemetry: false
```

**Events emitted:**

| Event | When | Measurements | Metadata |
|-------|------|-------------|----------|
| `[:ectomancer, :tool, :start]` | Tool execution begins | `system_time` | `:tool` |
| `[:ectomancer, :tool, :stop]` | Tool execution ends | `duration` | `:tool` |
| `[:ectomancer, :tool, :exception]` | Tool handler raises | `duration` | `:tool` |
| `[:ectomancer, :repo, :start]` | CRUD operation begins | `system_time` | `:action`, `:schema` |
| `[:ectomancer, :repo, :stop]` | CRUD operation ends | `duration` | `:action`, `:schema` |
| `[:ectomancer, :repo, :exception]` | Repo operation raises | `duration` | `:action`, `:schema` |
| `[:ectomancer, :authorization, :denied]` | Auth check fails | (none) | `:actor`, `:action`, `:handler` |
| `[:ectomancer, :rate_limit, :exceeded]` | Rate limit exceeded | (none) | `:key`, `:window_ms` |

**Example: Attaching a handler**

```elixir
:telemetry.attach("ectomancer-logger", [:ectomancer, :tool, :stop], fn _name, measurements, metadata, _config ->
  IO.puts("Tool #{metadata.tool} completed in #{System.convert_time_unit(measurements.duration, :native, :millisecond)}ms")
end, nil)
```

### Multi-repo

```elixir
expose MyApp.OtherSchema, repo: MyApp.ReplicaRepo
```

## Batch operations

Perform multi-record mutations in a single transactional call:

```elixir
expose MyApp.Accounts.User,
  actions: [:list, :get, :batch_create, :batch_update, :batch_destroy],
  batch_size: 200
```

| Action | Tool Name | Input | Behavior |
|--------|-----------|-------|----------|
| `batch_create` | `batch_create_users` | `records: [%{...}]` | Validates all, inserts in transaction |
| `batch_update` | `batch_update_users` | `records: [%{id, ...}]` | Fetches each, updates in transaction |
| `batch_destroy` | `batch_destroy_users` | `ids: [...]` | Fetches each, soft/hard-deletes atomically |

Partial failures are reported alongside successes — the AI assistant can retry or report the failed records:

```elixir
# Result shape: %{succeeded: [%{status: :ok, record: ...}], failed: [...], total: 3}
```

Batch operations respect authorization, scope, soft-delete, and field auth just like single-record operations.

## Upsert

Insert a new record or update an existing one in a single call based on a conflict target:

```elixir
expose MyApp.Products.Product,
  actions: [:upsert],
  conflict_target: :sku,
  on_conflict: :replace_all
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `conflict_target` | `atom \| [atom]` | (required) | Field(s) to check for existing records |
| `on_conflict` | `:replace_all \| [set: [...]]` | `:replace_all` | Which fields to update when a conflict is found |

Generated tool `upsert_product` accepts all writable fields. If a record matching the `conflict_target` exists, it's updated; otherwise, a new record is inserted.

**Return metadata** — the response indicates whether the record was inserted or updated:

```
{%MyApp.Products.Product{...}, :inserted}
{%MyApp.Products.Product{...}, :updated}
```

**Composite keys** — use a list for multi-field matching:

```elixir
expose MyApp.Inventory.Item,
  actions: [:upsert],
  conflict_target: [:org_id, :sku]
```

**Selective updates** — control which fields change on conflict:

```elixir
expose MyApp.Accounts.User,
  actions: [:upsert],
  conflict_target: :email,
  on_conflict: [set: [:name, :avatar_url]]
```

Upsert is **soft-delete aware** — upserting onto a soft-deleted record restores it (sets `deleted_at` to `nil`).

## Prompts

Define structured, parameterized prompt templates for LLM clients. Prompts are reusable blueprints that generate messages based on runtime arguments — the AI assistant can request them to kick off common workflows.

```elixir
prompt :summarize_reports do
  description "Summarize recent reports by type"
  argument :report_type, :string,
    required: true,
    description: "Type of report",
    enum: ["sales", "inventory", "employee"]

  messages fn args ->
    report_type = Map.get(args, "report_type", "sales")

    [
      %{
        role: :system,
        content: %{
          type: :text,
          text: "You are a report analyst. Summarize the #{report_type} reports."
        }
      },
      %{
        role: :user,
        content: %{
          type: :text,
          text: "Provide a concise summary of the latest #{report_type} reports."
        }
      }
    ]
  end
end
```

Prompts integrate with the MCP `prompts/list` and `prompts/get` protocol methods via `Anubis.Server.component/2`. Arguments support `required`, `default`, `description`, and `enum` constraints.

## Pages

| Path | Description |
|------|-------------|
| `/mcp` | MCP endpoint (Streamable HTTP) |
| `/mcp/sse` | SSE endpoint (legacy, transport: :sse) |
| `/mcp/ws` | WebSocket endpoint (via Phoenix socket) |

Open `priv/ectomancer.html` in a browser for a visual playground — browse tools, fill params, call them, and inspect results. No build step, no npm install, no dependencies.

## Documentation

- [HexDocs](https://hexdocs.pm/ectomancer)
- [GitHub Pages](https://gustavoZiaugra.github.io/ectomancer)
- [GitHub](https://github.com/GustavoZiaugra/ectomancer)

## Testing

```bash
mix test
```

Zero compiler warnings, full Credo and Dialyzer compliance.

Current version: **1.6.0**

## License

MIT
