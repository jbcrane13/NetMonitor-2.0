# Agent Readiness — NetMonitor-2.0

> **Read this before starting any work session on this project.**

## Current State

| Field | Value |
|-------|-------|
| Readiness level | **Level 5** |
| Pass rate | ~81% |
| Last updated | 2026-03-01 |
| Full report | https://app.factory.ai/analytics/readiness/https%253A%252F%252Fgithub.com%252Fjbcrane13%252Fnetmonitor-2.0 |

## Score History

| Session | Score | Δ | Key Work |
|---------|-------|---|----------|
| [00 — Initial Evaluation](./00-initial-evaluation.md) | 49% | — | Baseline audit across 81 criteria |
| [01 — Code Quality Tooling](./01-session-code-quality-tooling.md) | 66% | +17% | SwiftLint, SwiftFormat, pre-commit hooks, PR template, CODEOWNERS, Dependabot, lint CI |
| [02 — Agent Infrastructure](./02-session-agent-infrastructure.md) | 69% | +3% | Agent skills, release workflow, env template, AGENTS.md validation |
| [03 — Code Quality Analysis](./03-session-code-quality-analysis.md) | 79% | +10% | Periphery, jscpd, LogSanitizer, doc freshness CI, runbooks |
| [04 — Coverage Gates & Xcode 26 Fixes](./04-session-coverage-and-build-fixes.md) | 81% | +2% | Simulator destination, simd types, test mock conformance; NetworkScanKit 87.2% verified |

## Conventions Established

The following project conventions were introduced during readiness sessions. Respect them in all future work.

| Convention | Where configured | Rule |
|------------|-----------------|------|
| TODO format | `.swiftlint.yml` | `// TODO: (NetMonitor-2.0-xyz) description` — ticket ID required |
| SwiftFormat | `.swiftformat` | Correctness-only rules; run `swiftformat --lint .` to verify |
| Log scrubbing | `LogSanitizer.swift` | Wrap IPs, MACs, SSIDs, hostnames in `LogSanitizer.*` before logging |
| Logger categories | `Platform/Logging.swift` (macOS + iOS) | Use named `Logger.*` instances; do not create ad-hoc loggers |
| Dead code baseline | `.periphery.yml` | 117 baseline warnings exist; new warnings should be resolved or suppressed with justification |
| PR template | `.github/pull_request_template.md` | Auto-fills on PR open; include beads issue link |
| CODEOWNERS | `.github/CODEOWNERS` | Path-based ownership — respect when reviewing cross-boundary changes |

## Key Files Introduced

| File | Purpose |
|------|---------|
| `.factory/skills/run-tests/SKILL.md` | How to run tests (SSH to mac-mini required) |
| `.factory/skills/check-coverage/SKILL.md` | How to read and run coverage gates |
| `.factory/skills/create-release/SKILL.md` | End-to-end release procedure |
| `.factory/skills/fix-lint/SKILL.md` | Resolve SwiftLint and SwiftFormat failures |
| `.github/workflows/lint.yml` | Lint CI (SwiftLint, SwiftFormat, bare-TODO, AGENTS.md validation) |
| `.github/workflows/code-quality.yml` | Quality CI (dead code, duplicate code, log scrubbing, doc freshness) |
| `.github/workflows/release.yml` | Tag-triggered release pipeline |
| `Packages/NetMonitorCore/Sources/NetMonitorCore/Utilities/LogSanitizer.swift` | Log redaction utilities |

## How to Add a Session Report

1. Copy `SESSION-TEMPLATE.md` to `NN-session-slug.md` (increment the number)
2. Fill in all sections — delete placeholder lines, do not leave `[brackets]` in the final file
3. Update the Score History table in this README
4. Update the "Current State" block at the top
5. Commit both files together: `docs: agent readiness session NN — brief description`
