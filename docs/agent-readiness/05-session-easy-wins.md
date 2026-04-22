# Agent Readiness — Session 5: Easy Wins

**Date:** 2026-03-06
**Criteria addressed:** 6
**Score movement:** ~81% → ~88% (Level 5, solidifying)

---

## Summary

This session targeted the remaining low-effort, high-value criteria that had been identified but not yet addressed. Added GitHub issue templates (bug report and feature request) with YAML form syntax, created a project-specific label taxonomy via `gh label create`, documented the full iOS and macOS data model in a single reference doc, enforced serial test execution across all targets, added test timing extraction to the coverage CI workflow, and added a complexity metrics job to the code-quality CI workflow.

---

## What Was Implemented

### GitHub Issue Templates

Created `.github/ISSUE_TEMPLATE/` with three files:

- `bug_report.yml` — structured form with platform dropdown, version, OS version, reproduction steps, severity, and optional log attachment
- `feature_request.yml` — structured form with platform, motivation, proposed solution, alternatives, priority suggestion
- `config.yml` — enables blank issues and links to the GitHub issue tracker

Both templates note that the project uses GitHub Issues for agent-friendly issue tracking.

### GitHub Labels

Created 14 project-specific labels via `gh label create`:

| Label | Color | Purpose |
|-------|-------|---------|
| `triage` | yellow | Needs triage |
| `platform: macOS` | green | macOS target |
| `platform: iOS` | blue | iOS target |
| `platform: core` | purple | NetMonitorCore or NetworkScanKit |
| `P0: critical` | dark red | Security, data loss, broken builds |
| `P1: high` | red | Major features, important bugs |
| `P2: medium` | yellow | Default priority |
| `P3: low` | light green | Polish, optimization |
| `agent-ready` | light blue | Issue has enough context for an AI agent |
| `test` | lavender | Test coverage or infrastructure |
| `CI/CD` | teal | Build, lint, or deployment workflows |
| `companion-protocol` | cream | Mac-iOS companion communication |
| `performance` | blue | Performance improvement |
| `tech-debt` | gray | Code cleanup, refactoring |

### Data Model Documentation

Created `docs/data-model.md` documenting both persistence strategies:

- All 8 SwiftData `@Model` types with key fields and relationships
- Schema versioning approach (`SchemaV1` + migration plan)
- Concurrency notes for cross-actor SwiftData access
- iOS `AppSettings` key namespace (6 categories, ~25 keys)
- iOS `TargetManager` singleton behavior
- Platform comparison table (macOS vs iOS persistence)

### Test Isolation — Serial Execution Enforced

Updated all macOS test commands to include `-parallel-testing-enabled NO`, matching the iOS and Swift package test configurations:

- `AGENTS.md` test commands section
- `CLAUDE.md` SSH test command
- `.factory/skills/run-tests/SKILL.md`

All four test targets now run serially:
- macOS unit tests: `-parallel-testing-enabled NO`
- iOS unit tests: `-parallel-testing-enabled NO`
- NetMonitorCore: `swift test --no-parallel`
- NetworkScanKit: `swift test --no-parallel`

Suites with shared mutable state additionally use the `.serialized` trait (7 iOS suites already had this).

### Test Performance Tracking

Added a "Extract test timing" step to `.github/workflows/coverage-gates.yml` that:

- Parses xcodebuild log files for test duration
- Parses swift test output for package test duration
- Generates `build/coverage/test-timing.md` with a per-target timing table
- Uploads the timing report as part of the coverage artifacts

### Complexity Metrics

Added a `complexity-metrics` job to `.github/workflows/code-quality.yml` that:

- Runs SwiftLint with JSON reporter
- Extracts `cyclomatic_complexity` violations using Python
- Generates `build/complexity-report.md` with violation count, file/line/severity table
- Reports total Swift source files scanned
- Uploads the report as a CI artifact

---

## Criteria Fixed

| Criterion | Before | After |
|-----------|--------|-------|
| `issue_templates` | 0/1 | 1/1 |
| `issue_labeling_system` | 0/1 | 1/1 |
| `database_schema` | 1/2 | 2/2 |
| `test_isolation` | 1/2 | 2/2 |
| `test_performance_tracking` | 1/2 | 2/2 |
| `code_quality_metrics` | 1/2 | 2/2 |

---

## Files Created / Modified

| File | Action |
|------|--------|
| `.github/ISSUE_TEMPLATE/bug_report.yml` | Created |
| `.github/ISSUE_TEMPLATE/feature_request.yml` | Created |
| `.github/ISSUE_TEMPLATE/config.yml` | Created |
| `docs/data-model.md` | Created |
| `.github/workflows/coverage-gates.yml` | Modified — added test timing extraction step |
| `.github/workflows/code-quality.yml` | Modified — added complexity-metrics job |
| `.github/AGENTS.md` | Modified — added ISSUE_TEMPLATE directory |
| `AGENTS.md` | Modified — macOS test commands now use `-parallel-testing-enabled NO` |
| `CLAUDE.md` | Modified — macOS SSH test command now uses `-parallel-testing-enabled NO` |
| `.factory/skills/run-tests/SKILL.md` | Modified — macOS test command now uses `-parallel-testing-enabled NO` |

---

## Remaining Action Items

- Fix GeoLocation test crashes on Xcode 26 beta (pre-existing, blocks NetMonitorCore coverage)
- Fix `collect-and-gate.sh` conditional skip for `SKIP_XCODE_TESTS=1` (pre-existing)
- Consider adding `feature_flag_infrastructure` post-launch (deferred, requires design decision)
- Consider adding `error_tracking_contextualized` via Sentry post-launch (deferred, privacy decision)
