# Agent Instructions

This project uses **GitHub Issues** (`gh` CLI) for issue tracking. Repo: `jbcrane13/NetMonitor-2.0`.

## Quick Reference

```bash
gh issue list --repo jbcrane13/NetMonitor-2.0 --label "status:ready" --state open --json number,title,labels
gh issue edit <number> --repo jbcrane13/NetMonitor-2.0 --add-label "status:in-progress" --remove-label "status:ready"
gh issue close <number> --repo jbcrane13/NetMonitor-2.0 --comment "Done: <summary>"
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

---

## Project Overview

Monorepo: macOS + iOS network monitoring apps sharing a core Swift package.
**Swift 6.0** with strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`).
**Build tool:** XcodeGen — run `xcodegen generate` after modifying `project.yml`.
**Deployment targets:** macOS 15.0, iOS 18.0.

```
NetMonitor-macOS ─┐
                  ├─→ NetMonitorCore ─→ NetworkScanKit
NetMonitor-iOS  ──┘
```

| Path | Purpose |
|------|---------|
| `Packages/NetMonitorCore/` | Shared models, protocols, services (~5,600 LOC) |
| `Packages/NetworkScanKit/` | Multi-phase network discovery engine (~2,200 LOC) |
| `NetMonitor-macOS/` | macOS app (SwiftData, menu bar, shell services) |
| `NetMonitor-iOS/` | iOS app (companion, widget, liquid glass UI) |

## Build Commands

```bash
xcodegen generate                                              # Regenerate Xcode project
xcodebuild -scheme NetMonitor-macOS -configuration Debug build # Build macOS
xcodebuild -scheme NetMonitor-iOS -configuration Debug build   # Build iOS
```

## Test Commands

**⚠️ Tests run on `mac-mini` via SSH — never run `xcodebuild test` locally.**

```bash
# All macOS unit tests (parallel MUST be disabled — Swift 6 strict concurrency + @MainActor tests)
xcodebuild test -scheme NetMonitor-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:NetMonitor-macOSTests 2>&1 | tail -30

# Single test suite (macOS)
xcodebuild test -scheme NetMonitor-macOS -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:NetMonitor-macOSTests/ShellPingResultTests 2>&1 | tail -20

# All iOS unit tests (parallel MUST be disabled)
xcodebuild test -scheme NetMonitor-iOS \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:NetMonitor-iOSTests 2>&1 | tail -30

# Swift package tests
cd Packages/NetMonitorCore && swift test --no-parallel
cd Packages/NetworkScanKit && swift test --no-parallel
```

## Linting

```bash
swiftlint lint --quiet                  # Check all — errors block commits
swiftlint --fix --quiet                 # Auto-fix correctable violations
swiftformat --lint .                    # Check formatting
swiftformat .                           # Auto-fix formatting
```

Config: `.swiftlint.yml`, `.swiftformat`. Pre-commit hook runs both on staged files.

---

## Code Style

### Imports
Unsorted (no enforced order). Conventional grouping: Foundation → Apple frameworks → project packages. In tests: `import Testing` first, then `@testable import`.

### Formatting
- 4-space indentation, LF line endings
- Line length: 150 warning / 250 error (URLs, comments, interpolated strings exempt)
- Guard-else on next line
- No trailing commas
- Use `// MARK: - Section Name` to organize type members

### Naming Conventions

| Kind | Convention | Example |
|------|-----------|---------|
| Files | Match primary type | `DashboardView.swift`, `PingServiceProtocol` in `ServiceProtocols.swift` |
| Views | `*View` | `DashboardView`, `PingToolView` |
| ViewModels | `*ViewModel` | `DashboardViewModel`, `GeoTraceViewModel` |
| Services | `*Service` | `ShellPingService`, `WiFiInfoService` |
| Protocols | `*Protocol` suffix | `PingServiceProtocol`, `DeviceDiscoveryServiceProtocol` |
| Mocks (tests) | `Mock*` prefix | `MockPingService`, `MockGatewayService` |
| Test suites | `*Tests` suffix | `ShellPingResultTests`, `DashboardViewModelTests` |
| Booleans | `is*`/`has*`/`needs*` | `isConnected`, `isScanning`, `hasError` |
| Accessibility IDs | `{screen}_{element}_{descriptor}` | `"dashboard_card_healthScore"` |
| TODOs | Must reference GitHub issue | `// TODO: (#123) description` |

### Types and Access Control
- **Packages:** Explicit `public` on all API types, inits, and methods. Omit `internal`.
- **App targets:** Default access (internal). `private`/`private(set)` for implementation details.
- **Protocol existentials:** Always use `any` keyword — `any PingServiceProtocol`, not bare protocol name.
- **Type inference:** Preferred for stored properties with initial values. Explicit for protocol-typed deps.

### Concurrency
- **ViewModels:** `@MainActor @Observable final class`. State is `private(set) var`.
- **Services:** Actor types or `Sendable` protocol conformance. All service protocols are `Sendable`.
- **Mocks:** `@unchecked Sendable` (or `@MainActor` if testing MainActor-isolated code).
- **Streaming ops:** `AsyncStream<T>` for ping, port scan, traceroute (never throw).
- **Atomic ops:** `async throws` with typed `NetworkError`.

### Error Handling
- **Streaming results:** `AsyncStream<T>` — never throws; errors embedded in result type.
- **Atomic operations:** `async throws` with `NetworkError` enum (has `.errorDescription` and `.userFacingMessage`).
- **Optional return:** For "no result" scenarios (e.g., `DNSQueryResult?`).
- **ViewModels:** Surface errors as `errorMessage: String?` — never throw from VM methods.

### ViewModel Pattern
```swift
@MainActor @Observable final class FooViewModel {
    private(set) var isLoading = false          // Observable state
    private let service: any FooServiceProtocol // Injected dependency
    init(service: any FooServiceProtocol = FooService()) { ... } // DI with production default
    func load() async { ... }                  // Public async methods
}
```

### Test Pattern
Uses **Swift Testing** framework (not XCTest). `#expect` for assertions, `@Test` for test functions.
```swift
@Suite("FooService") struct FooServiceTests {
    @Test func parsesValidInput() { #expect(result == expected) }
}
@Suite("FooViewModel") @MainActor struct FooViewModelTests {
    func makeVM() -> FooViewModel { FooViewModel(service: MockFooService()) }
    @Test func loadSetsState() async { ... }
}
```
Key patterns: `@MainActor` on suites testing ViewModels, `.serialized` trait for shared mutable state, `waitUntil {}` helper instead of `Task.sleep`, `defer` for global state cleanup.

### Logging
Use `os.Logger` with named categories (defined in `Platform/Logging.swift`). **Scrub sensitive data:**
```swift
Logger.network.debug("IP: \(LogSanitizer.redactIP(addr))")     // IPs
Logger.discovery.info("MAC: \(LogSanitizer.redactMAC(mac))")    // MACs
Logger.network.debug("SSID: \(LogSanitizer.redactSSID(ssid))")  // SSIDs
```
Never log raw IPs, MACs, SSIDs, or hostnames outside `LogSanitizer` wrappers.

## Code Quality Tools

| Tool | Command | Purpose |
|------|---------|---------|
| SwiftLint | `swiftlint lint --quiet` | Style and correctness errors |
| SwiftFormat | `swiftformat --lint .` | Formatting violations |
| Periphery | `periphery scan --quiet` | Unused declarations (dead code) |
| jscpd | `jscpd --languages swift .` | Duplicate code detection |

CI runs all four on every PR via `lint.yml` and `code-quality.yml`. Periphery and jscpd are warning-only and do not block merges.

---

## Reference Docs

| Document | Location |
|----------|----------|
| Agent Readiness (**read first**) | `docs/agent-readiness/README.md` |
| Architecture Decision Records | `docs/ADR.md`, `docs/ADR-macOS.md` |
| Companion Protocol (Mac↔iOS) | `docs/Companion-Protocol-API.md` |
| Testing Lessons Learned | `docs/TESTING-LESSONS-LEARNED.md` |
| Coverage Gates | `docs/testing/coverage-gates.md` |
| iOS PRD | `docs/NetMonitor iOS Companion - Product Requirements Document.md` |
| macOS PRD | `docs/NetMonitor for macOS - Product Requirements Document.md` |

**Runbooks:** `.factory/skills/run-tests/`, `check-coverage/`, `create-release/`, `fix-lint/` — each has `SKILL.md`.

## Issue Tracking with GitHub Issues

**IMPORTANT**: This project uses **GitHub Issues via `gh` CLI** for ALL issue tracking. Do NOT use `bd`/beads, markdown TODOs, or other tracking methods.

### Quick Start

```bash
# Check ready work
gh issue list --repo jbcrane13/NetMonitor-2.0 --label "status:ready" --state open --json number,title,labels

# Create issue
gh issue create --repo jbcrane13/NetMonitor-2.0 --title "Title" --body "Details" --label "type:feature,priority:medium,status:ready"

# Claim task
gh issue edit <number> --repo jbcrane13/NetMonitor-2.0 --add-label "status:in-progress" --remove-label "status:ready" --add-assignee "@me"

# Close when done
gh issue close <number> --repo jbcrane13/NetMonitor-2.0 --comment "Done: <summary>"
```

### Label Schema

**Type:** `type:bug` · `type:feature` · `type:task` · `type:epic` · `type:chore`
**Priority:** `priority:critical` · `priority:high` · `priority:medium` · `priority:low` · `priority:backlog`
**Status:** `status:ready` · `status:in-progress` · `status:blocked` · `status:review`
**Agent:** `agent:daneel` · `agent:quentin`

### Rules

- ✅ Use GitHub Issues for ALL task tracking
- ✅ Label every issue with type + priority + status
- ✅ Use milestones for phases (v2.1, v2.2, Backlog)
- ❌ Do NOT use `bd` / beads
- ❌ Do NOT create markdown TODO lists

