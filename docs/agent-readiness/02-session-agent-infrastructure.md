# Agent Readiness — Session 2: Agent Infrastructure

**Date:** 2026-02-28
**Commits:** `edcca57` (pushed to main)
**Criteria addressed:** 5
**Score movement:** ~66% → ~69% (consolidating Level 4)

---

## Context

This session focused on infrastructure that directly enables and informs the two agent assistants working on this project: agent-runnable skills, a release workflow, environment documentation, and CI validation that AGENTS.md stays accurate.

---

## What Was Implemented

### `.env.example`

Documents that no runtime environment variables are required. Lists dev tool prerequisites (xcodegen, swiftlint, swiftformat, bd) and a placeholder section for future Sentry/analytics secrets that CI would need.

### Agent Skills — `.factory/skills/`

Four skills written specifically for agent assistants. Skills are in `.factory/skills/{name}/SKILL.md` format with YAML frontmatter. Both agent assistants have access to these.

#### `run-tests`
Complete SSH command reference for running tests on mac-mini. Covers:
- Unit tests for macOS, iOS, and both Swift packages
- UI tests (require signed build + active GUI session on mac-mini)
- How to sync the repo to mac-mini before running
- How to run a specific test suite or single test class
- How to interpret pass/fail output

**Critical note embedded in skill:** Local `xcodebuild test` is blocked by a PreToolUse hook and will hang on UI tests. All tests must run via SSH to mac-mini.

#### `check-coverage`
Coverage gate reference. Covers:
- Coverage thresholds table (iOS 30%, macOS 20%, NetMonitorCore 40%, NetworkScanKit 38%)
- Full SSH command to run `scripts/coverage/collect-and-gate.sh`
- Fast variants: `SKIP_XCODE_TESTS=1` or `SKIP_PACKAGE_TESTS=1`
- How to read PASS/FAIL output and coverage artifacts
- Guidance on which test file to add when a threshold is failing

#### `create-release`
End-to-end release procedure. Covers:
- Gate: checking the release prep checklist (`bd show NetMonitor-2.0-c0p`)
- Verifying clean state (git status, lint, format)
- Bumping version in `project.yml` (CFBundleShortVersionString + CFBundleVersion for both targets)
- Creating and pushing a semver tag
- Monitoring the `release.yml` workflow via gh CLI
- Reviewing and publishing the draft GitHub Release
- Closing the release prep beads issue
- Version convention (semver + build number)

#### `fix-lint`
SwiftLint and SwiftFormat troubleshooting guide. Covers:
- Auto-fix commands (`swiftlint --fix`, `swiftformat .`)
- Common errors and their fixes: `todo_needs_ticket`, `force_unwrapping`, `cyclomatic_complexity`, `type_body_length`, `identifier_name`, `line_length`
- How to suppress a violation with a justification comment
- Reference table of all lint-related config files

### Release Workflow — `.github/workflows/release.yml`

Triggers on any `v*` tag push. Runs:

1. **`validate`** — SwiftLint strict + SwiftFormat lint gate (blocks if failing)
2. **`build-macos`** — `xcodebuild build -configuration Release` for macOS (parallel with iOS)
3. **`build-ios`** — `xcodebuild build -configuration Release` for iOS (parallel with macOS)
4. **`release`** — Creates a **draft** GitHub Release with auto-generated notes

The release is always created as a draft so it can be reviewed before publishing. To publish:
```bash
gh release edit v2.0.0 --draft=false
```

### AGENTS.md Validation — added to `lint.yml`

New `agents-md-validation` CI job verifies on every PR:
- `scripts/hooks/install-hooks.sh` and `scripts/coverage/collect-and-gate.sh` exist and are executable
- `xcodegen`, `swiftlint`, `swiftformat` are available on the runner
- A dry-run build validates the documented build commands are syntactically correct
- All `.factory/skills/*/SKILL.md` files have valid `name:` and `description:` frontmatter

### `.github/AGENTS.md` Updated

Rewritten to reflect the current state of `.github/`. Now includes:
- File table (CODEOWNERS, dependabot.yml, pull_request_template.md)
- Workflow table with trigger and purpose for all three workflows
- Agent guidance for adding workflows, triggering releases, checking run status
- Available skills reference

---

## Criteria Fixed

| Criterion | Before | After |
|-----------|--------|-------|
| `env_template` | 0/1 | 1/1 |
| `skills` | 0/1 | 1/1 |
| `release_notes_automation` | 0/1 | 1/1 |
| `release_automation` | 0/1 | 1/1 |
| `agents_md_validation` | 0/1 | 1/1 |

---

## Files Created / Modified

| File | Action |
|------|--------|
| `.env.example` | Created |
| `.factory/skills/run-tests/SKILL.md` | Created |
| `.factory/skills/check-coverage/SKILL.md` | Created |
| `.factory/skills/create-release/SKILL.md` | Created |
| `.factory/skills/fix-lint/SKILL.md` | Created |
| `.github/workflows/release.yml` | Created |
| `.github/workflows/lint.yml` | Modified — added `agents-md-validation` job |
| `.github/AGENTS.md` | Rewritten |

---

## Triggering a Release (for agents)

```bash
# 1. Verify checklist complete
bd show NetMonitor-2.0-c0p

# 2. Bump version in project.yml, then:
xcodegen generate
git add project.yml NetMonitor-2.0.xcodeproj/
git commit -m "chore: bump version to 2.0.1 (build 16)"
git push

# 3. Tag and push
git tag -a v2.0.1 -m "NetMonitor 2.0.1"
git push origin v2.0.1

# 4. Monitor workflow
gh run list --workflow=release.yml --limit 5

# 5. Publish draft release when ready
gh release edit v2.0.1 --draft=false

# 6. Close beads issue
bd close NetMonitor-2.0-c0p && bd sync && git push
```
