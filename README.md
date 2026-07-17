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
- **Custom resources** — `resource :system_status do ... end` with URI templates, MIME types, and authorization
- **Rate limiting** — configurable token bucket per tool or globally
- **Multi-repo support** — expose schemas from different repos simultaneously
- **MCP Resources** — schemas auto-register at `ectomancer://schemas/{name}`, plus custom resources with URI templates, MIME types, and read handlers
- **Browser playground** — zero-dep HTML client at `priv/ectomancer.html`, no build step
- **Oban integration** — optional bridge for inspecting queue depth and workers
- **Interactive installer** — `mix ectomancer.setup` auto-discovers schemas and patches your project

## Demo

Watch Ectomancer in action — a full Phoenix app with User, Post, and Comment schemas exposed as MCP tools, running on the Streamable HTTP transport.

![Ectomancer Demo](priv/demo.gif)

*3 Ecto schemas → 15 MCP tools with zero boilerplate. Replay locally with `asciinema play priv/demo.cast`.*

The demo shows:
- **3 Ecto schemas** → **15 MCP tools** (list, get, create, update, destroy) with zero boilerplate
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

```elixir
def deps do
  [
    {:ectomancer, "~> 1.5"}
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
end
```

### 2. Start the MCP server

Add to your Application supervisor:

```elixir
children = [
  # ... other children ...
  {Anubis.Server.Supervisor, {MyApp.MCP, transport: {:streamable_http, start: true}}},
  MyAppWeb.Endpoint
]
```

### 3. Mount in your router

```elixir
scope "/mcp" do
  pipe_through :api
  forward "/", Ectomancer.Plug, server: MyApp.MCP
end
```

### 4. Configure actor extraction (optional)

```elixir
config :ectomancer,
  repo: MyApp.Repo,
  actor_from: fn conn ->
    conn.assigns.current_user
  end
```

Done. Claude can now query your database through natural language at `/mcp`.

## Authorization

Three strategies, choose what fits:

| Style | Example | Use case |
|-------|---------|----------|
| **Inline** | `authorize fn actor, _ -> actor.role == :admin end` | Quick rules |
| **Policy module** | `authorize with: MyApp.Policies.UserPolicy` | Complex logic, reusable |
| **None** | `authorize :none` | Public endpoints |

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

## Pages

| Path | Description |
|------|-------------|
| `/mcp` | MCP endpoint (SSE + JSON-RPC) |

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

Current version: **1.5.0**

## License

MIT
