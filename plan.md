# PhoenixMcp — Project Plan

> Add an AI brain to your Phoenix app in one afternoon.

A library that automatically exposes your Phoenix/Ecto app as an MCP (Model Context Protocol) server, making it conversationally operable by Claude and other LLMs with minimal configuration.

---

## What it does

`PhoenixMcp` sits on top of [Hermes MCP](https://github.com/cloudwalk/hermes-mcp) (or its fork `anubis_mcp`) and does two things Hermes doesn't:

1. **Auto-generates MCP tools** from your Ecto schemas — no hand-writing tool definitions
2. **Threads the current user (actor)** through every tool call automatically — auth just works

```elixir
# In your router — one line
forward "/mcp", PhoenixMcp.Plug

# In a dedicated module — describe what to expose
defmodule MyApp.MCP do
  use PhoenixMcp

  expose MyApp.Accounts.User,
    actions: [:list, :get, :create, :update],
    only: [:id, :email, :name, :role]

  expose MyApp.Blog.Post,
    actions: [:list, :get],
    except: [:internal_notes]

  tool :send_password_reset do
    description "Send a password reset email to a user"
    param :email, :string, required: true
    handle fn %{email: email}, actor ->
      MyApp.Accounts.send_reset_email(email, actor)
    end
  end
end
```

---

## What Claude gains access to

Once connected, Claude can:

- Query data in natural language ("show me users who signed up this week but haven't onboarded")
- Run multi-step workflows ("create the account, assign the starter plan, send the welcome email")
- Perform bulk operations based on conditions
- Give support agents a conversational admin interface
- Serve as a lightweight BI layer over your data
- Inspect queue depth, stuck jobs, and background workers (with optional Oban bridge)

---

## Architecture overview

```
User prompt
    │
    ▼
Claude (MCP client)
    │  JSON-RPC over HTTP/SSE
    ▼
PhoenixMcp.Plug          ← extracts actor from conn
    │
    ▼
Hermes.Server            ← handles MCP protocol, sessions
    │
    ▼
PhoenixMcp components    ← generated at compile time from your schemas
    │
    ▼
Your Ecto Repo / Context functions
```

### Three internal layers

**Layer 1 — ToolGenerator** (compile time)
Reads `__schema__(:fields)`, `:types`, `:associations` and generates Hermes-compatible tool component modules automatically.

**Layer 2 — Server wrapper** (runtime)
Wraps `Hermes.Server`, resolves the current actor from the connection, and threads it into `frame.assigns` so every tool handler can access it.

**Layer 3 — Plug** (HTTP)
Thin wrapper around `Hermes.Server.Transport.StreamableHTTP.Plug` that handles actor extraction before handing off to the MCP transport layer.

---

## Dependency note

Hermes MCP was forked and rebranded to `anubis_mcp` starting at v0.13.0 after the original author left CloudWalk. You should decide at project start which to depend on — or abstract over both with a behaviour. Worth watching both repos before cutting a v0.1 release.

---

## Roadmap

### Phase 0 — Foundation (~2 days)
**Goal:** Shippable `v0.1` — any Phoenix dev can wire up a custom MCP with minimal boilerplate.

- [ ] **Hermes MCP integration layer** — wrap Hermes, define `PhoenixMcp` behaviour, wire up JSON-RPC transport
- [ ] **Phoenix plug + router mount** — one-line `forward "/mcp"` setup, SSE and HTTP transport support
- [ ] **Actor threading** — extract current user from conn (Bearer, session, API key) and thread into every tool call
- [ ] **Custom tool DSL** — define arbitrary tools with `tool :name do ... end`, typed params, and a handler fn

### Phase 1 — Ecto auto-exposure (~3 days)
**Goal:** Shippable `v0.2` — the killer feature. `expose MySchema` and CRUD tools appear automatically.

- [ ] **Schema introspection** — read `__schema__(:fields)`, `:types`, `:associations` at compile time to generate tool input shapes
- [ ] **CRUD tool generation** — auto-generate `list_X`, `get_X`, `create_X`, `update_X` from a single `expose` call
- [ ] **Ecto type → JSON Schema mapping** — map Ecto types (`:string`, `:integer`, `Ecto.UUID`, embeds) to proper MCP JSON Schema input definitions
- [ ] **Field filtering** — per-schema `only:` and `except:` to control what Claude can read or write

### Phase 2 — Authorization + DX (~3 days)
**Goal:** Shippable `v0.3` — production-safe, trustworthy for real apps.

- [ ] **Authorization hooks** — pluggable auth: inline fn, delegate to policy module, or `:none`. Per-schema and per-action granularity
- [ ] **Auto descriptions from docs** — pull `@moduledoc` and field descriptions to auto-generate Claude-readable tool descriptions
- [ ] **Changeset error translation** — map Ecto changeset errors to structured MCP error responses Claude can reason about
- [ ] **Read-only mode** — global or per-schema `read_only: true` flag that disables all write tools at the library level

### Phase 3 — Power features (~1 week)
**Goal:** `v1.0` — a platform, not just a library.

- [ ] **Route introspection** — auto-discover Phoenix routes via `Router.__routes__/0` and expose them as callable tools
- [ ] **Oban bridge** — expose queue depth, stuck jobs, retry tools (optional dep, only activates if Oban is present)
- [ ] **Relationship traversal** — follow `has_many` / `belongs_to` associations so Claude can navigate data naturally
- [ ] **`ash_mcp` extension** — separate package, Ash resource extension that auto-exposes actions, policies, and calculations with zero config

---

## API design

### `expose/2` — schema auto-exposure

```elixir
expose MyApp.Accounts.User,
  actions: [:list, :get, :create, :update, :destroy],
  only: [:id, :email, :name],           # whitelist fields
  except: [:password_hash, :secret],    # or blacklist
  read_only: false,                     # default false
  authorize: fn actor, action ->        # optional inline auth
    actor.role == :admin or action in [:list, :get]
  end
```

**Generated tools:**
- `list_users` — paginated list with optional filters
- `get_user` — fetch by primary key
- `create_user` — inserts via your Repo
- `update_user` — updates via your Repo

### `tool/2` — custom tools

```elixir
tool :transfer_funds do
  description "Transfer funds between two accounts"
  param :from_account_id, :string, required: true
  param :to_account_id,   :string, required: true
  param :amount,          :float,  required: true

  handle fn %{from_account_id: from, to_account_id: to, amount: amount}, actor ->
    MyApp.Finance.transfer(from, to, amount, actor: actor)
  end
end
```

### Authorization hooks

```elixir
# Option 1: inline function
authorize fn actor, action ->
  actor.role == :admin or action == :get
end

# Option 2: delegate to a policy module
authorize with: MyApp.Policies.UserPolicy

# Option 3: no auth (internal tools, trusted callers)
authorize :none
```

### Actor extraction (configurable)

```elixir
# In config/config.exs
config :phoenix_mcp,
  actor_from: fn conn ->
    conn
    |> get_req_header("authorization")
    |> MyApp.Auth.resolve_user()
  end
```

---

## Module structure

```
lib/
├── phoenix_mcp.ex                  ← use macro, main DSL entry point
└── phoenix_mcp/
    ├── plug.ex                     ← Phoenix router integration, actor extraction
    ├── server.ex                   ← Hermes.Server wrapper
    ├── tool_generator.ex           ← Ecto schema → Hermes components (compile time)
    ├── schema_builder.ex           ← Ecto types → JSON Schema types
    ├── tool.ex                     ← custom tool DSL
    └── authorizer.ex               ← auth hook system
```

---

## Ecto → JSON Schema type mapping

| Ecto type | JSON Schema type |
|-----------|-----------------|
| `:string` | `string` |
| `:integer` | `integer` |
| `:float` | `number` |
| `:boolean` | `boolean` |
| `:date` | `string` (format: date) |
| `:datetime` / `:utc_datetime` | `string` (format: date-time) |
| `Ecto.UUID` | `string` (format: uuid) |
| `{:array, inner}` | `array` with inner items type |
| `:map` / embeds | `object` |

---

## Open questions to resolve before v0.1

- **Hermes vs anubis_mcp** — pick one, or abstract over both with a behaviour
- **Compile-time vs runtime tool registration** — recommendation: compile-time for `expose`, runtime for `tool` DSL
- **Default pagination** — what's the default page size for `list_X` tools? Make it configurable
- **Naming collisions** — what happens when two schemas produce a `list_users` tool? Namespace by context?
- **Transport default** — StreamableHTTP only, or also STDIO for local dev?

---

## Launch checklist

- [ ] Working v0.1 with custom tool DSL (Phase 0)
- [ ] Working v0.2 with Ecto auto-exposure (Phase 1)
- [ ] Demo video: Phoenix app becomes conversationally operable in 5 minutes
- [ ] Sample app (cloneable, runnable immediately)
- [ ] Solid README with exact 3-line setup
- [ ] Hex package registered: `phoenix_mcp`
- [ ] HexDocs with full API reference
- [ ] ElixirForum post + Twitter/X announcement

---

## Prior art and references

- [Hermes MCP](https://github.com/cloudwalk/hermes-mcp) — Elixir MCP SDK (server + client)
- [anubis_mcp](https://hex.pm/packages/anubis_mcp) — fork of Hermes from v0.13.0+
- [MCP specification](https://spec.modelcontextprotocol.io) — official protocol spec
- [Ash Framework](https://ash-hq.org) — if you later want to build `ash_mcp`, the resource metadata layer is already there
