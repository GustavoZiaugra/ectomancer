# Ectomancer — Claude Instructions

Ectomancer is an Elixir library that exposes Phoenix/Ecto applications as MCP (Model Context Protocol) servers, making them operable by LLMs with minimal configuration.

## Commands

```bash
mix test              # run the full test suite
mix format            # auto-format all source files
mix credo             # static analysis — must pass with zero warnings
mix dialyzer          # type checking — run before PRs
mix docs              # generate documentation
```

## Code Quality Rules

- **Zero Credo warnings.** All issues reported by `mix credo` must be resolved before committing.
- **Zero compiler warnings.** `mix compile` must be clean.
- **Formatter compliance.** Always run `mix format` before committing.
- Keep cyclomatic complexity ≤ 9. Extract private helpers when a function grows beyond this.
- Maximum function body nesting depth: 2. Use guard clauses or helper functions to flatten.
- Prefer `if` over `unless` with an `else` block.
- Use `Enum.map_join/3` instead of `Enum.map/2 |> Enum.join/2`.
- Avoid `length/1` for emptiness checks — use `== []` or `Enum.empty?/1`.
- Aliases must be sorted alphabetically within their group.

## Architecture

| Layer | Modules | Responsibility |
|---|---|---|
| DSL | `Ectomancer`, `Ectomancer.Expose`, `Ectomancer.Tool` | Public macros for schema exposure and custom tools |
| Authorization | `Ectomancer.Authorization`, `Ectomancer.Authorization.Policy` | Inline, policy-module, and action-specific auth |
| Integration | `Ectomancer.Plug`, `Ectomancer.Repo`, `Ectomancer.ObanBridge`, `Ectomancer.Server` | Phoenix plug, Ecto CRUD, Oban job management, server lifecycle |
| Introspection | `Ectomancer.SchemaIntrospection`, `Ectomancer.SchemaBuilder`, `Ectomancer.RouteIntrospection` | Compile-time metadata extraction and JSON schema generation |
| Installer | `Ectomancer.Installer.*`, `Ectomancer.Igniter`, `Mix.Tasks.Ectomancer.Setup` | Interactive setup, schema discovery, config file patching |

Optional dependencies (Phoenix, Ecto, Oban, Plug) are declared as optional in `mix.exs` and must be guarded accordingly.

## Workflow

- All changes go through a PR — **never push directly to `main`**.
- Branch naming: `feat/`, `fix/`, `refactor/`, `chore/` prefixes.
- Run `mix test && mix credo && mix format` locally before opening a PR.
- Do not add `Co-Authored-By` trailers to commits.
