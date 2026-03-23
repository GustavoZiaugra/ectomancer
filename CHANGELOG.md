# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0-rc.3] - 2026-03-23

### Added

#### Read-Only Mode (Phase 2)
- **Read-only schema exposure** - Disable mutations with `readonly: true`
  ```elixir
  expose MyApp.Blog.Post, readonly: true
  ```
- Only generates `:list` and `:get` tools
- Prevents create, update, destroy operations
- Useful for public-facing schemas or reference data

#### Changeset Error Mapping (Phase 2)
- **Detailed validation error responses** - MCP error format for changeset errors
  ```json
  {
    code: -32602,
    message: "Missing required field(s)",
    data: { errors: [{field: "Email", message: "can't be blank"}] }
  }
  ```
- **Error categorization** - Auto-categorize validation types:
  - `presence` - Missing required fields
  - `format` - Invalid format (email regex, etc.)
  - `inclusion` - Value not in allowed set
  - `confirmation` - Confirmation doesn't match
  - `length` - String length issues
  - `comparison` - Numeric comparison failures

#### Schema Changeset Integration
- Uses schema's custom `changeset/2` function when available
- Ensures unique_constraint validations are properly applied
- Returns structured errors instead of raw Postgrex exceptions

### Changed
- Updated README.md with read-only mode and error handling documentation
- Enhanced error handling with better categorization
- Updated test count to 193 tests

### Fixed
- Fixed constraint violation handling - uses schema changesets
- Fixed error messages for validation failures

### Testing
- **193 tests** (up from 172)
- **6 read-only mode tests**
- **16 changeset error mapping tests**
- Full integration tested
- Zero compiler warnings
- Full Credo and Dialyzer compliance

### Issues Closed
- [#12](https://github.com/GustavoZiaugra/ectomancer/issues/12) - Implement read-only mode
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
