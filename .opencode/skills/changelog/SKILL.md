---
name: changelog
description: Generate or update CHANGELOG.md entries from git log for Hex.pm releases. Extracts what changed, categorizes by type (Added/Changed/Fixed/Deprecated/Removed/Security), detects breaking changes, and enriches entries with examples, configuration snippets, and upgrade notes.
---

# Generate Changelog for Hex.pm Release

Generate a complete changelog entry by analyzing commits since the last tag, researching each feature's implementation, and writing detailed entries suitable for Hex.pm publication.

## Workflow

### Step 1: Discover Commits Since Last Tag

```bash
git log --oneline --format="%h %s" $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD
git log --oneline $(git describe --tags --abbrev=0)..HEAD --format="%s"
```

Group commits by type:
- `feat:` / `feature:` → **Added**
- `fix:` → **Fixed**
- `refactor:` → **Changed** (only if user-facing)
- `docs:` → skip (unless docs-only release)
- BREAKING / `!:` → **Breaking change** / prefix with `### ⚠️ Breaking Changes`

### Step 2: Diff Against Existing Unreleased Section

Read `CHANGELOG.md` Unreleased section. If it already has entries, cross-reference with the git log to:
- Remove duplicates (already in CHANGELOG)
- Identify commits missing from CHANGELOG
- Identify commits that are internal-only (refactors, test-only, tooling) — skip these unless the change is architecturally significant

### Step 3: Research Each New Feature

For each feature not yet documented, use the `task` tool with `subagent_type: "explore"` to research the implementation. Request:

1. The macro/function signature
2. Configuration options and defaults
3. How it works (3 sentence max)
4. Example usage from README or tests
5. Whether it has authorization/scope/soft-delete integration
6. Whether it changes any existing behavior (breaking?)
7. The return format

### Step 4: Detect Breaking Changes

Check each commit and feature for:
- Modified existing macros or functions (not additive)
- Changed default behavior
- Removed options or deprecations
- Changed return types
- Updated minimum dependency versions

If any are found, add a `### ⚠️ Breaking Changes` section at the top of the release entry.

### Step 5: Write the Changelog Entry

Format per [Keep a Changelog](https://keepachangelog.com/en/1.0.0/):

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- **Feature name** — brief description (#PR)
  Longer explanation with bullet points.

  Configuration example (if applicable):
  ```elixir
  expose MyApp.Accounts.User,
    actions: [:feature],
    feature_option: :value
  ```

  Return format:
  ```elixir
  {:ok, %{...}}
  ```

### Changed
- Only if user-facing behavior changed

### Fixed
- Bug fixes with issue/PR references

### Deprecated / Removed / Security
- As needed
```

**Enrichment rules:**
- Each top-level bullet must have: feature name bolded, PR number, and at least one sentence of explanation
- Include a ` ```elixir ``` ` config snippet if the feature has configuration options
- Include the return/response format if it's a new tool or function
- Mention integration with existing systems (auth, scoping, soft-delete, telemetry)
- If there's a README section, reference it by line
- End the entry with `**No breaking changes**` or the breaking changes summary

### Step 6: Update CHANGELOG.md

1. Move content from `## [Unreleased]` into the new release section
2. Add the new `[X.Y.Z]` tag link at the bottom
3. Update `[Unreleased]` link to point to `compare/vX.Y.Z...HEAD`
4. Update date to today

### Step 7: Verify

Read the final CHANGELOG.md, confirm:
- All commits since last tag are accounted for
- No duplicates between Unreleased and new section
- Examples are syntactically valid Elixir
- PR numbers are present
- Date is today
- Tag links at bottom are updated

## Examples

### Good entry (batch operations):

```markdown
### Added
- **Batch operations** — three new transactional actions: `batch_create`, `batch_update`, `batch_destroy` (#109)

  Enable per schema:
  ```elixir
  expose MyApp.Accounts.User,
    actions: [:batch_create, :batch_update, :batch_destroy],
    batch_size: 200
  ```

  All three run inside a single `repo.transaction`. Invalid records are collected without aborting valid ones. Returns `%{succeeded: [...], failed: [...], total: N}`.

  `batch_size` (default: `100`) is enforced before any DB interaction. Exceeding it returns MCP error code `-32602`. Full authorization, scope, and soft-delete support.
```

### Weak entry (too terse — don't do this):

```markdown
### Added
- Batch operations: batch_create, batch_update, batch_destroy (#109)
```

## Project-Specific Conventions (Ectomancer)

- Optional dependencies (`phoenix`, `ecto`, `oban`) are loaded only if parent app uses them — never mention them as required
- All features should note authorization/scope/soft-delete integration where applicable
- Tool naming follows `{action}_{resource}` pattern (e.g., `batch_create_users`)
- Default values are always documented (e.g., `batch_size: 100`)
- If the feature changes nothing about existing behavior, explicitly say "No breaking changes"
