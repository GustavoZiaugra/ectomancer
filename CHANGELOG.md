# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### Phoenix Route Introspection (Issue #14)
- New `expose_routes/1` macro to auto-generate MCP tools from Phoenix router
- Support for all HTTP methods: GET, POST, PUT, PATCH, DELETE
- Smart tool naming with automatic singularization:
  - `/users` → `get_users`, `post_users`
  - `/users/:id` → `get_user`, `put_user`, `delete_user`
- Route filtering options:
  - `:only` - Include only specific paths
  - `:except` - Exclude specific paths  
  - `:methods` - Filter by HTTP methods
  - `:namespace` - Prefix tool names (e.g., `api_get_users`)
- Automatic path parameter mapping to tool parameters
- Direct controller action execution via `Plug.Test.conn`
- Proper handling of `Plug.Conn.AlreadySentError`

```elixir
# Expose all routes
expose_routes MyAppWeb.Router

# With filtering
expose_routes MyAppWeb.Router,
  only: ["/api/users"],
  namespace: :api,
  methods: ["GET", "POST"]
```

## [0.1.0-rc.3] - 2026-03-18

### Added

#### Read-Only Mode (Issue #12)
- New `:readonly` option for `expose/2` macro
- When `readonly: true`, only generates `:list` and `:get` tools
- Prevents create, update, destroy operations
- Perfect for public read-only access to data

```elixir
expose MyApp.Blog.Post, readonly: true
# Generates only: list_posts, get_post
```

#### Changeset Error Mapping (Issue #13)
- Enhanced error messages from Ecto changeset validations
- Automatic categorization of validation errors:
  - **presence**: Missing required fields
  - **format**: Invalid format (email regex, etc.)
  - **inclusion**: Value not in allowed set
  - **confirmation**: Confirmation doesn't match
  - **length**: String length issues
  - **comparison**: Numeric comparison failures

- Improved database error detection:
  - **unique_violation**: "Duplicate value: Record with this value already exists"
  - **foreign_key_violation**: "Invalid reference: Related record does not exist"
  - **not_null_violation**: "Missing required parameter: Field Name"

- Schema changeset integration
  - Uses schema's `changeset/2` function when available
  - Ensures unique_constraint validations work properly
  - Returns structured error responses instead of binary strings

### Changed
- Updated README.md with read-only mode and error handling documentation
- Enhanced error categorization in `format_error/1`

### Fixed
- Fixed unique constraint violations to return proper error responses
- Fixed foreign key violations to show descriptive messages
- Fixed changeset validation errors to show field names and messages

### Testing
- **193 tests** (up from 172)
- **21 new tests**: 16 for read-only mode, 6 for error mapping
- Full integration tested with sweetcorn Phoenix app
- All authorization strategies still working

### Issues Closed
- [#12](https://github.com/GustavoZiaugra/ectomancer/issues/12) - Implement read-only mode for expose macro
- [#13](https://github.com/GustavoZiaugra/ectomancer/issues/13) - Map Ecto changeset errors to MCP error responses

## [0.1.0-rc.2] - 2026-03-17

### Added

#### Authorization System (Phase 2)
- **Inline function authorization** - Simple auth checks with inline functions
  ```elixir
  authorize fn actor, action -> actor.role == :admin end
  ```
- **Policy module authorization** - Reusable authorization logic via behavior
  ```elixir
  authorize with: MyApp.Policies.UserPolicy
  ```
- **Public access** - `:none` authorization for public endpoints
  ```elixir
  authorize :none
  ```
- **Per-schema authorization** - Global auth rules for all actions on a schema
- **Per-action authorization** - Fine-grained control with action-specific rules
- **Authorization cascade** - Multiple auth levels work together

#### Binary ID / UUID Support
- Full support for `binary_id` primary keys
- Automatic UUID string casting
- Works with all CRUD operations

#### Enhanced Error Messages
- Descriptive error messages (e.g., "Missing required parameter: User id")
- Proper MCP error codes (-32602 for validation, -32603 for internal)
- Field identification in error responses

### Changed
- Updated README.md with comprehensive authorization documentation
- Improved error handling with better error categorization

### Fixed
- Fixed binary_id primary key handling in get/update/destroy operations
- Fixed Peri validation compatibility with JSON Schema format
- Fixed tool parameter generation for nested blocks
- Fixed atom vs string key handling in normalize_params

### Security
- SQL injection prevention via parameterized queries
- Row limits to prevent memory exhaustion (100 records default)
- Authorization checks before tool execution
- Proper error messages without exposing internal details

### Testing
- **172 tests** (up from 128)
- **35 authorization-specific tests**
- All authorization strategies tested
- Full integration tested with sweetcorn Phoenix app

### Issues Closed
- [#10](https://github.com/GustavoZiaugra/ectomancer/issues/10) - Design and implement authorization hook system
- [#11](https://github.com/GustavoZiaugra/ectomancer/issues/11) - Add per-schema and per-action authorization granularity
- [#35](https://github.com/GustavoZiaugra/ectomancer/issues/35) - Fix critical bugs in binary ID handling and tool parameter schemas

## [0.1.0-rc.1] - 2026-03-16

### Added
- First release candidate with fully functional CRUD operations
- Core MCP server implementation via `Ectomancer` module
- `expose/2` macro for auto-generating CRUD tools from Ecto schemas (list, get, create, update, destroy)
- `tool/2` macro for custom tool definitions with param validation
- `Ectomancer.Plug` for seamless Phoenix router integration
- `Ectomancer.Repo` abstraction supporting all major CRUD operations
- Automatic actor extraction and threading through `conn.assigns`
- Field filtering support via `:only` and `:except` options
- Namespace support to prevent tool naming collisions
- Comprehensive test suite (128 tests, all passing)
- Full Credo and Dialyzer compliance
- Support for Phoenix 1.7 and 1.8
- MIT License

### Fixed
- Fixed Peri schema validation crashes by disabling params in exposed tools
- Fixed GenServer crashes during CRUD operations with proper error handling
- Fixed tool execution to return proper Anubis Response format
- Fixed repo error handling with comprehensive try/rescue blocks

### Security
- SQL injection prevention via parameterized queries in Repo operations
- Row limits to prevent memory exhaustion (100 records default)
- Proper error messages without exposing internal details

[Unreleased]: https://github.com/GustavoZiaugra/ectomancer/compare/v0.1.0-rc.3...HEAD
[0.1.0-rc.3]: https://github.com/GustavoZiaugra/ectomancer/releases/tag/v0.1.0-rc.3
[0.1.0-rc.2]: https://github.com/GustavoZiaugra/ectomancer/releases/tag/v0.1.0-rc.2
[0.1.0-rc.1]: https://github.com/GustavoZiaugra/ectomancer/releases/tag/v0.1.0-rc.1
