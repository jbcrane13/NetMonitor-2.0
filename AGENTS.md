# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

<!-- MANUAL: Project documentation below -->

---

## Project Overview

NetMonitor-2.0 is a monorepo containing macOS and iOS network monitoring apps sharing a core Swift package.

**Build tool:** XcodeGen — run `xcodegen generate` after modifying `project.yml`.
**Swift:** 6.0 with strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`).
**Targets:** macOS 15.0, iOS 18.0.

## Dependency Chain

```
NetMonitor-macOS ─┐
                  ├─→ NetMonitorCore ─→ NetworkScanKit
NetMonitor-iOS  ──┘
```

## Key Directories

| Path | Purpose |
|------|---------|
| `Packages/NetMonitorCore/` | Shared models, protocols, and services |
| `Packages/NetworkScanKit/` | Multi-phase network device discovery engine |
| `NetMonitor-macOS/` | macOS app (SwiftData, menu bar, shell services) |
| `NetMonitor-iOS/` | iOS app (companion, widget, liquid glass UI) |
| `docs/` | Architecture docs, ADRs, companion protocol spec |

## First-time Setup

After cloning, install the git hooks (required for pre-commit linting):

```bash
scripts/hooks/install-hooks.sh
```

This points `core.hooksPath` at `.githooks/`, which runs SwiftLint on staged Swift files and enforces a 2 MB file size limit on every commit. Requires SwiftLint (`brew install swiftlint`).

## Build Commands

```bash
xcodegen generate                                    # Regenerate .xcodeproj from project.yml
xcodebuild -scheme NetMonitor-macOS -configuration Debug build
xcodebuild -scheme NetMonitor-iOS -configuration Debug build
xcodebuild test -scheme NetMonitor-macOS
xcodebuild test -scheme NetMonitor-iOS
```

## Linting

```bash
swiftlint lint --quiet                               # Lint entire codebase
swiftlint lint --quiet NetMonitor-macOS/             # Lint a single directory
swiftlint --fix                                      # Auto-fix correctable violations
```

Configuration: `.swiftlint.yml` at repo root. Errors block commits via pre-commit hook; warnings are reported but do not block.

## Agent Readiness

Before starting work, read **`docs/agent-readiness/README.md`**. It describes the current readiness level, coding conventions introduced by previous sessions (TODO format, log scrubbing rules, dead-code baseline, etc.), and which skill files to use for common agent tasks.

## Runbooks & Reference Docs

| Document | Location | Purpose |
|----------|----------|---------|
| Agent Readiness | `docs/agent-readiness/README.md` | Current readiness score, conventions, key files — **read first** |
| Architecture Decision Records | `docs/ADR.md`, `docs/ADR-macOS.md` | Why key design decisions were made — read before changing patterns |
| Companion Protocol | `docs/Companion-Protocol-API.md` | Mac↔iOS wire protocol spec — required reading before touching CompanionService |
| Shared Codebase Plan | `docs/NETMONITOR-2.0-SHARED-CODEBASE-PLAN.md` | Monorepo architecture rationale |
| Testing Lessons Learned | `docs/TESTING-LESSONS-LEARNED.md` | Common test pitfalls and patterns specific to this project |
| SwiftUI Best Practices | `docs/SwiftUI Best Practices.md` | Project-specific UI conventions |
| iOS PRD | `docs/NetMonitor iOS Companion - Product Requirements Document.md` | Feature requirements for iOS target |
| macOS PRD | `docs/NetMonitor for macOS - Product Requirements Document.md` | Feature requirements for macOS target |
| Coverage Gates | `docs/testing/coverage-gates.md` | How coverage thresholds are enforced and how to read results |

**Agent workflow runbooks** (step-by-step procedures):

| Skill | Purpose |
|-------|---------|
| `.factory/skills/run-tests/SKILL.md` | Run tests on mac-mini via SSH |
| `.factory/skills/check-coverage/SKILL.md` | Run and interpret coverage gates |
| `.factory/skills/create-release/SKILL.md` | End-to-end release procedure |
| `.factory/skills/fix-lint/SKILL.md` | Resolve SwiftLint and SwiftFormat failures |

## Logging Guidelines

All logging uses `os.Logger` with named subsystem categories. Logger instances are defined in:
- `NetMonitor-macOS/Platform/Logging.swift`
- `NetMonitor-iOS/Platform/Logging.swift`

**Log scrubbing is required for network-identifying data.** Use `LogSanitizer` (in `NetMonitorCore/Utilities/LogSanitizer.swift`) when logging values that could identify users or their location:

```swift
// IP addresses
Logger.network.debug("Connecting to \(LogSanitizer.redactIP(ipAddress))")

// MAC addresses
Logger.discovery.info("Found device \(LogSanitizer.redactMAC(macAddress))")

// Hostnames / SSIDs
Logger.network.debug("SSID: \(LogSanitizer.redactSSID(ssid))")
```

`LogSanitizer` passes values through unmodified in `DEBUG` builds and redacts them in `Release` builds. Never log raw IPs, MACs, SSIDs, or hostnames outside of `LogSanitizer` wrappers.

## Code Quality Tools

| Tool | Command | Purpose |
|------|---------|---------|
| SwiftLint | `swiftlint lint --quiet` | Style and correctness errors |
| SwiftFormat | `swiftformat --lint .` | Formatting violations |
| Periphery | `periphery scan --quiet` | Unused declarations (dead code) |
| jscpd | `jscpd --languages swift .` | Duplicate code detection |

CI runs all four on every PR via `lint.yml` and `code-quality.yml`. Periphery and jscpd are warning-only and do not block merges.

## Core Patterns

- **Service protocols** defined in `NetMonitorCore/Services/ServiceProtocols.swift`; implemented per-platform
- **AsyncStream<T>** for streaming results (ping, port scan, traceroute)
- **@MainActor @Observable** ViewModels (iOS) — views contain no business logic
- All service protocols are `Sendable`; strict Swift 6 concurrency enforced

