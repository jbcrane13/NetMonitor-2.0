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

## Build Commands

```bash
xcodegen generate                                    # Regenerate .xcodeproj from project.yml
xcodebuild -scheme NetMonitor-macOS -configuration Debug build
xcodebuild -scheme NetMonitor-iOS -configuration Debug build
xcodebuild test -scheme NetMonitor-macOS
xcodebuild test -scheme NetMonitor-iOS
```

## Core Patterns

- **Service protocols** defined in `NetMonitorCore/Services/ServiceProtocols.swift`; implemented per-platform
- **AsyncStream<T>** for streaming results (ping, port scan, traceroute)
- **@MainActor @Observable** ViewModels (iOS) — views contain no business logic
- All service protocols are `Sendable`; strict Swift 6 concurrency enforced

