# AGENTS.md - Ectomancer

## Project Overview

Ectomancer is an Elixir library that automatically exposes Phoenix/Ecto applications as MCP (Model Context Protocol) servers. It provides:

1. Auto-generated MCP tools from Ecto schemas
2. Automatic user/actor threading through tool calls
3. Plug integration for Phoenix routers

## Tech Stack

- **Language**: Elixir (~> 1.18)
- **Framework**: Mix project (library)
- **Core Dependencies**:
  - anubis_mcp (~> 0.17) - MCP server implementation
  - jason (~> 1.4) - JSON handling
  - phoenix (~> 1.7) - optional
  - ecto (~> 3.12) - optional
  - plug (~> 1.16) - optional
- **Dev Tools**: credo, ex_doc, dialyxir

## Common Commands

```bash
# Install dependencies
mix deps.get

# Compile
mix compile

# Run tests
mix test

# Check formatting
mix format --check-formatted

# Run static analysis
mix credo

# Run Dialyzer (type checking)
mix dialyzer

# Generate documentation
mix docs

# Interactive shell
iex -S mix
```

## Code Style

- Follow standard Elixir conventions (snake_case for variables/functions, CamelCase for modules)
- Use `mix format` to auto-format code
- Run `mix credo` before committing to catch style issues
- Prefer pattern matching over conditionals
- Use `|>` pipe operator for data transformation pipelines
- Document public functions with `@doc` and `@spec`

## Architecture

- `lib/ectomancer.ex` - Main module with `use Ectomancer` macro
- `lib/ectomancer/server.ex` - MCP server implementation
- `lib/ectomancer/tool.ex` - Tool generation from Ecto schemas
- `lib/ectomancer/plug.ex` - Phoenix Plug for HTTP endpoint
- `lib/ectomancer/application.ex` - OTP application
- `test/` - ExUnit test files

## Testing

- Use ExUnit for testing
- Run `mix test` to execute all tests
- Tests are in `test/` directory matching `lib/` structure
- Use `mix test.watch` (if installed) for continuous testing during development

## Important Notes

- This is a library, not an application (no `config/runtime.exs`)
- Optional dependencies are loaded only if parent app uses them
- The library provides macros and utilities, not a standalone service
- Always maintain backward compatibility when possible

## MCP Context

Ectomancer is a meta-project - it's a library for building MCP servers. When working on this codebase, you're building tools that enable AI assistants (like Claude) to interact with Phoenix/Ecto applications conversationally.

## Release Process

To create a new release:

1. **Create release branch**
   ```bash
   git checkout -b release/vX.Y.Z
   ```

2. **Update version in `mix.exs`** (line 5)
   - Change `@version "old_version"` to new version

3. **Update `CHANGELOG.md`**
   - Add new release section under `[Unreleased]`
   - Include: Added, Changed, Fixed, Testing, Issues Closed
   - Update `[Unreleased]` URL to point to new tag

4. **Update `README.md`**
   - Line 17: Update version in installation example
   - Update current version note at end of file

5. **Commit changes**
   ```bash
   git add .
   git commit -m "Release vX.Y.Z: Brief description"
   ```

6. **Create pull request**
   - Create PR from release branch to main
   - Wait for review/approval

7. **After merge - Create git tag and push**
   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

8. **Create GitHub release**
   ```bash
   gh release create vX.Y.Z --title "vX.Y.Z - Title" --notes "..."
   ```

9. **(Optional) Publish to Hex.pm**
   ```bash
   mix hex.publish
   ```
