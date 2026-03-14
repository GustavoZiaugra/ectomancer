# Ectomancer

> Add an AI brain to your Phoenix app in one afternoon.

**Ectomancer** automatically exposes your Phoenix/Ecto app as an MCP (Model Context Protocol) server, making it conversationally operable by Claude and other LLMs with minimal configuration.

## What it does

Ectomancer sits on top of [anubis_mcp](https://hex.pm/packages/anubis_mcp) and provides two killer features:

1. **Auto-generates MCP tools** from your Ecto schemas — no hand-writing tool definitions
2. **Threads the current user (actor)** through every tool call automatically — auth just works

## Installation

```elixir
def deps do
  [
    {:ectomancer, "~> 0.1.0"}
  ]
end
```

## Quick Start (3 lines)

```elixir
# In your router — one line
forward "/mcp", Ectomancer.Plug

# In a dedicated module — describe what to expose
defmodule MyApp.MCP do
  use Ectomancer

  # Custom tools
  tool :send_password_reset do
    description "Send a password reset email to a user"
    param :email, :string, required: true
    handle fn %{email: email}, actor ->
      MyApp.Accounts.send_reset_email(email, actor)
    end
  end
end
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
- Full documentation and examples coming soon

## Status

This project is in active development. Phase 0 (Foundation) is currently being implemented.

## License

MIT License - see LICENSE file for details.

