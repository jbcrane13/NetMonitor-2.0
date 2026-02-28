---
name: fix-lint
description: Fix SwiftLint errors and SwiftFormat violations in NetMonitor-2.0. Use when the pre-commit hook blocks a commit, the CI lint job fails, or before opening a PR. Errors block commits; warnings do not.
---

# Fix Lint — NetMonitor-2.0

## Quick check — what's failing?

```bash
swiftlint lint --quiet              # All violations (errors + warnings)
swiftlint lint --quiet --reporter xcode  # Xcode-style paths (click to jump in editor)
swiftformat --lint .                # Format violations
```

## Auto-fix everything auto-fixable

```bash
swiftlint --fix --quiet             # Fixes: trailing whitespace, comma spacing, colon spacing, etc.
swiftformat .                       # Fixes: semicolons, empty braces, guard-else, etc.
```

Always re-run after auto-fixing to confirm no errors remain:

```bash
swiftlint lint --quiet | grep ": error:" | wc -l   # Must be 0 before committing
swiftformat --lint .                                # Must show 0 files
```

## Common errors and how to fix them

### `todo_needs_ticket` — TODO without beads ID
```swift
// Bad:
// TODO: fix this later

// Good:
// TODO: (NetMonitor-2.0-xyz) fix this later
```
File the beads issue first (`bd create`), then reference it.

### `force_unwrapping` — force unwrap (`!`)
```swift
// Bad:
let value = someOptional!

// Good:
guard let value = someOptional else { return }
// or:
let value = someOptional ?? defaultValue
```

### `cyclomatic_complexity` — function too complex
Break the function into smaller private helper functions. Threshold: warning at 12, error at 20.

### `type_body_length` — struct/class too large
Extract logical groupings into extensions or separate types.

### `identifier_name` — variable name too short
```swift
// Bad (1 char not in allowed list):
let n = items.count

// Good:
let itemCount = items.count
```
Allowed single-char names: `i`, `j`, `k`, `x`, `y`, `z`, `id`, `ip`.

### `line_length` — line too long
Break long lines. Warning at 150 chars, error at 250. Comments and URLs are exempt.

## Lint-related files

| File | Purpose |
|------|---------|
| `.swiftlint.yml` | All SwiftLint rules and thresholds |
| `.swiftformat` | SwiftFormat rules (correctness-only baseline) |
| `.githooks/pre-commit` | Runs both tools on staged files before each commit |
| `.github/workflows/lint.yml` | CI jobs: swiftlint + swiftformat + bare-TODO check |

## Suppress a specific violation (use sparingly)

```swift
// swiftlint:disable:next force_unwrapping
let image = UIImage(named: "logo")!  // guaranteed to exist in bundle

// For a whole scope:
// swiftlint:disable force_unwrapping
...
// swiftlint:enable force_unwrapping
```

Always add a comment explaining why suppression is justified.
