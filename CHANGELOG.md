# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/GustavoZiaugra/ectomancer/compare/v0.1.0-rc.1...HEAD
[0.1.0-rc.1]: https://github.com/GustavoZiaugra/ectomancer/releases/tag/v0.1.0-rc.1
