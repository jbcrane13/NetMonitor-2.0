# Agent Instructions

The single source of rules for every agent working in this repo (Claude Code, Codex, Hermes and others). Add shared rules here. `CLAUDE.md` holds only what is specific to Claude Code.

## Environment note (Hermes)

Hermes agent profiles set `$HOME` to an isolated directory (e.g. `/Users/blake/.hermes/profiles/<name>/home`), so tools that read config from `$HOME`, especially **Claude Code** and **`gh`**, can't find their credentials. Prefix those commands with `HOME=/Users/blake`:

```bash
HOME=/Users/blake claude auth status
HOME=/Users/blake gh issue list --repo jbcrane13/NetMonitor-2.0
HOME=/Users/blake claude --acp --stdio
```

## Project Overview

Monorepo: macOS + iOS network monitoring apps sharing two Swift packages. Swift 6 with strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`); deployment targets macOS 15.0, iOS 18.0.

```
NetMonitor-macOS ─┐
                  ├─→ NetMonitorCore ─→ NetworkScanKit
NetMonitor-iOS  ──┘
```

| Path | Purpose |
|------|---------|
| `Packages/NetMonitorCore/` | Shared models, service protocols, core services |
| `Packages/NetworkScanKit/` | Multi-phase network discovery engine |
| `NetMonitor-macOS/` | macOS app (SwiftData, menu bar, shell-based services) |
| `NetMonitor-iOS/` | iOS app (companion connection, widget, liquid glass UI) |
| `Tests/` | Unit and UI test targets |
| `docs/` | Architecture docs, ADRs, companion protocol spec |

### NetMonitorCore

Defines every service protocol in `Services/ServiceProtocols.swift`; platform targets implement them. Services include DeviceDiscovery, Ping, PortScanner, DNS, WHOIS, Bonjour, Traceroute, SpeedTest, WakeOnLAN, NetworkMonitor, Notification and MACVendorLookup. Key enums: `DeviceType`, `StatusType`, `DeviceStatus`, `ConnectionType`, `ToolType`, `TargetProtocol`, `DNSRecordType`, `PortScanPreset` (in `Models/Enums.swift`), and `SpeedTestPhase`, `ScanDisplayPhase` (in `Services/ServiceProtocols.swift`).

### NetworkScanKit

Multi-phase scanning pipeline:

1. ARP scan + Bonjour (concurrent)
2. TCP probe + SSDP (concurrent)
3. ICMP latency enrichment (sequential)
4. Reverse DNS resolution (sequential)

Key types: `ScanEngine`, `ScanPipeline`, `ScanContext`, `ScanAccumulator`, `ConnectionBudget`, `ThermalThrottleMonitor`.

### macOS scan pipeline

`DeviceDiscoveryCoordinator.startScan()` runs: ARP → Bonjour → merge → name resolution → vendor lookup → quick port scan (27 ports: `QuickPortScanPhase.commonPorts`, the device fingerprint ports plus the security-rule ports) → device type inference → latency (3 pings) → final merge through Core `ScanReconciler` (shared with iOS: `PresenceMatch` picks the row, and a row goes offline only under `DeviceGracePolicy`, 3 missed scans and 15 minutes; #596). `DeviceTypeInferenceService` classifies unknown devices from hostname, services, ports and vendor.

## Platform Differences

| Concern | macOS | iOS |
|---|---|---|
| Ping | Shells to `/sbin/ping` via `ShellCommandRunner` | Network framework / companion |
| ARP scan | Shells to `arp` | Sysctl BSD API (`ARPCacheScanner`) |
| ICMP | Raw `ICMPSocket` | Via companion or NetworkScanKit |
| Persistence | SwiftData (`NetworkTarget`, `LocalDevice`, `SessionRecord`) | `AppSettings` + `TargetManager` |
| UI theme | `MacTheme` (see macOS UI below) | Liquid glass (`Theme`, `GlassCard`, `GlassButton`) |
| Background | — | `BGTaskScheduler` |
| Mac link | Advertises `_netmon._tcp` on port 8849 | Discovers and connects via `MacConnectionService` |
| Wi-Fi signal | CoreWLAN (`CWInterface`): RSSI, noise, channel | Shortcuts "Get Network Details" → `SaveWiFiReadingIntent` (~2 s round trip); `NEHotspotNetwork` fallback (SSID/BSSID only) |
| Heatmap service | `WiFiHeatmapService` (CoreWLAN wrapper) | `IOSHeatmapService` (Shortcuts + NEHotspotNetwork) |

## Mac–iOS Companion Protocol

Bonjour `_netmon._tcp`, port 8849, 4-byte big-endian length-prefixed JSON frames over `NWConnection`, capped at 1 MiB (`CompanionFrameDecoder.defaultMaximumFrameSize`). `CompanionMessage` (`Models/CompanionMessage.swift` in NetMonitorCore) defines the wire format for both sides. Message types: `statusUpdate`, `targetList`, `deviceList`, `networkProfile`, `command`, `toolResult`, `error`, `heartbeat`. Spec: `docs/Companion-Protocol-API.md`.

## Worktree Setup

Run `bash scripts/setup-worktree.sh` in every new worktree before starting work, and configure the worktree manager to run it and wait for success before starting the agent. The script locates its own checkout, so an absolute-path invocation works too.

Setup checks Xcode, XcodeGen, SwiftLint, SwiftFormat and `gh`; configures `.githooks` per worktree; enables and verifies the codex-review gate (`~/.claude/scripts/enable-review-gate.sh`; set `SKIP_REVIEW_GATE=1` on a host without Codex); regenerates the Xcode project; and resolves pinned Swift packages. It stops on missing tools, incomplete Xcode setup, existing edits to generated files, or new generated-file/lockfile drift: review the failure before proceeding. On a detached HEAD, create a `codex/<issue-or-task>` branch before committing.

Setup leaves secrets, `.env` files, tool installs, builds, tests, branches, pulls and pushes alone. Use it rather than `.factory/init.sh`, which is Heatmap-specific and builds both apps.

## Build

XcodeGen generates the `.xcodeproj` from `project.yml`; run `xcodegen generate` after every `project.yml` change.

```bash
xcodegen generate
xcodebuild -scheme NetMonitor-macOS -configuration Debug build
xcodebuild -scheme NetMonitor-iOS -configuration Debug build
swift build -c debug   # from Packages/NetMonitorCore or Packages/NetworkScanKit
```

## Test Execution Policy

Run `xcodebuild test` on a test host, never in an ad-hoc local session:

- **mini-pro-2** (`ssh blakes-mac-mini-2`) is the automation node, preferred when it is reachable and has disk space. Run there over SSH from its checkout:

  ```bash
  ssh blakes-mac-mini-2 "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-macOS -configuration Debug …"
  ```

- **mini-pro-1** is the current host while mini-pro-2 is unavailable. Run there after consulting Blake when he is actively using that machine; if he is not present, you may run there without consulting. Every run there goes through the shared lock and a timeout, so one hung run can't block the other workers:

  ```bash
  lockf -t 7200 /tmp/nm-mini1-test.lock timeout 1200 xcodebuild test … -derivedDataPath <private dir>
  ```

  A log holding only the `lockf` line means the run never started; it is not a test failure.

On either host:

- Use a private DerivedData directory **outside** the source tree. Shared DerivedData fails with "database is locked", and inside the tree the SwiftLint build phase lints the SPM checkouts and fails.
- Disable parallel testing (`-parallel-testing-enabled NO`, `swift test --no-parallel`): Swift 6 strict concurrency and `@MainActor` suites need it.
- Pick the iOS simulator by `id=` from `xcrun simctl list devices available`; mini-pro-1 has an "iPhone 17" but no "iPhone 17 Pro".
- Before trusting a log, grep it for `Test run with`, `Restarting after unexpected` and `Fatal error`. xcodebuild hides crashing suites, so a green summary alone is not evidence.

```bash
# macOS unit tests (add /SuiteName to -only-testing for a single suite)
xcodebuild test -scheme NetMonitor-macOS -configuration Debug -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO -derivedDataPath <private dir> \
  -only-testing:NetMonitor-macOSTests

# iOS unit tests
xcodebuild test -scheme NetMonitor-iOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=<iPhone 17 id>' \
  CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO -derivedDataPath <private dir> \
  -only-testing:NetMonitor-iOSTests

# macOS UI tests (signed build and a GUI session)
xcodebuild test -scheme NetMonitor-macOS -configuration Debug -destination 'platform=macOS' \
  -only-testing:NetMonitor-macOSUITests

# Swift packages
cd Packages/NetMonitorCore && swift test --no-parallel
cd Packages/NetworkScanKit && swift test --no-parallel
```

## Linting and Code Quality

| Tool | Command | Purpose |
|------|---------|---------|
| SwiftLint | `swiftlint lint --quiet` (`swiftlint --fix --quiet` to auto-fix) | Style and correctness errors |
| SwiftFormat | `swiftformat --lint .` (`swiftformat .` to auto-fix) | Formatting violations |
| Periphery | `periphery scan --quiet` | Unused declarations (dead code) |
| jscpd | `jscpd --languages swift .` | Duplicate code detection |

Config: `.swiftlint.yml`, `.swiftformat`. The pre-commit hook runs SwiftLint and `swiftformat --lint` on staged Swift files; their errors block the commit. CI runs all four on every PR via `lint.yml` and `code-quality.yml`; Periphery and jscpd are warning-only.

## Code Style

### Imports
No enforced order. Conventional grouping: Foundation → Apple frameworks → project packages. In tests: `import Testing` first, then `@testable import`.

### Formatting
- 4-space indentation, LF line endings
- Line length: 150 warning / 250 error (URLs, comments, interpolated strings exempt)
- Guard-else on next line
- No trailing commas
- `// MARK: - Section Name` to organize type members

### Naming Conventions

| Kind | Convention | Example |
|------|-----------|---------|
| Files | Match primary type | `DashboardView.swift`, `PingServiceProtocol` in `ServiceProtocols.swift` |
| Views | `*View` | `DashboardView`, `PingToolView` |
| ViewModels | `*ViewModel`, in `NetMonitor-iOS/ViewModels/` on iOS | `DashboardViewModel`, `GeoTraceViewModel` |
| Services | `*Service` | `ShellPingService`, `WiFiInfoService` |
| Protocols | `*Protocol` suffix, in `ServiceProtocols.swift` | `PingServiceProtocol`, `DeviceDiscoveryServiceProtocol` |
| Mocks (tests) | `Mock*` prefix | `MockPingService`, `MockGatewayService` |
| Test suites | `*Tests` suffix | `ShellPingResultTests`, `DashboardViewModelTests` |
| Booleans | `is*`/`has*`/`needs*` | `isConnected`, `isScanning`, `hasError` |
| Accessibility IDs | `{screen}_{element}_{descriptor}` | `dashboard_card_healthScore`, `dashboard_device_card_192.168.1.1` |
| TODOs | Reference a GitHub issue | `// TODO: (#123) description` |

### Types and Access Control
- **Packages:** explicit `public` on all API types, inits and methods. Omit `internal`.
- **App targets:** default (internal) access; `private`/`private(set)` for implementation details.
- **Protocol existentials:** always `any`: `any PingServiceProtocol`.
- **Type inference:** for stored properties with initial values; explicit types for protocol-typed dependencies.

### Concurrency
- **ViewModels:** `@MainActor @Observable final class`, state as `private(set) var`. Views contain no business logic.
- **Services:** `Sendable`; services that touch state are actors or `@MainActor`. Every service protocol is `Sendable`, and every service is protocol-backed for DI and testability.
- **Mocks:** `@unchecked Sendable` (or `@MainActor` when testing MainActor-isolated code).
- **Streaming ops** (ping, port scan, traceroute): `AsyncStream<T>` for incremental results.
- **Atomic ops:** `async throws` with typed `NetworkError`.

### Error Handling
- **Streaming results:** `AsyncStream<T>` never throws; errors are embedded in the result type.
- **Atomic operations:** `async throws` with `NetworkError` (has `.errorDescription` and `.userFacingMessage`).
- **No result:** optional return (e.g. `DNSQueryResult?`).
- **ViewModels:** surface errors as `errorMessage: String?`; VM methods don't throw.

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
**Swift Testing** (not XCTest): `@Test` functions, `#expect` assertions.
```swift
@Suite("FooService") struct FooServiceTests {
    @Test func parsesValidInput() { #expect(result == expected) }
}
@Suite("FooViewModel") @MainActor struct FooViewModelTests {
    func makeVM() -> FooViewModel { FooViewModel(service: MockFooService()) }
    @Test func loadSetsState() async { ... }
}
```
Key patterns: `@MainActor` on suites testing ViewModels, `.serialized` for shared mutable state, the `waitUntil {}` helper instead of `Task.sleep`, `defer` for global state cleanup.

### Logging
`os.Logger` with named categories (defined in each app's `Platform/Logging.swift`). Pass every IP, MAC, SSID and hostname through `LogSanitizer`:
```swift
Logger.network.debug("IP: \(LogSanitizer.redactIP(addr))")
Logger.discovery.info("MAC: \(LogSanitizer.redactMAC(mac))")
Logger.network.debug("SSID: \(LogSanitizer.redactSSID(ssid))")
```

## macOS UI

**Text contrast (light + dark).** macOS views use `MacTheme` (`MacTheme.swift`) with explicit adaptive colors. On glass cards and app surfaces use `MacTheme.Colors.labelSecondary` / `labelTertiary` / `labelQuaternary` (legends, axis labels) instead of `.secondary`/`.tertiary`, which are too dim on dark glass and washed out on light glass; `textSecondary`/`textTertiary` remain for general text. Use `MacTheme` colors rather than `Color.white.opacity(...)`, which breaks light mode. Keep system `.secondary` where the system draws the background: native `Form`/Settings panes, native `List`s (e.g. Timeline), the menu bar popover, `ContentUnavailableView`. Chart wells, dividers and empty bar tracks use `chartSurface`, `chartSurfaceShallow`, `chartGridline`, `cardDivider`, `hairline`.

**Pro mode table.** `ProModeRowView` defines the shared column widths (`statusWidth`, `ipWidth`, …) that `DevicesView.proModeHeaderRow` references; keep header and rows in sync through those constants.

**Keyboard shortcuts** are defined in `KeyboardShortcutsModifier` (`ContentView.swift`): ⌘1–4 sidebar nav, ⌘R rescan, ⌘K quick jump, ⌘T quick tool. Put many `.background { Button… }` shortcuts in one `ViewModifier` with a single `.background` containing a `Group`; chaining five or more times out the Swift type-checker.

### Shared components

Check these before building a one-off.

| Component | File | Purpose |
|---|---|---|
| `MiniSparklineView` | `NetMonitor-macOS/Views/Components/MiniSparklineView.swift` | Sparkline with threshold coloring and dual overlays |
| `CardStateViews` | `NetMonitor-macOS/Views/Components/CardStateViews.swift` | Shimmer/skeleton/empty/error card states; use instead of a bare `ProgressView()` |
| `QuickJumpSheet` | `NetMonitor-macOS/Views/Components/QuickJumpSheet.swift` | ⌘K device search overlay |
| `DashboardLayout` | `NetMonitor-macOS/Views/NetworkDetailView.swift` | Breakpoints: compact (<1200 pt), standard (1200–1599 pt), wide (≥1600 pt) |

Cross-platform patterns:

- **Tool categories:** Diagnostics, Discovery, Monitoring, Actions on both platforms (`ToolCategory` on macOS, `IOSToolCategory` on iOS, with different tool sets).
- **Device quick actions:** `quickActionBar` in both DeviceDetailViews: Ping, Scan Ports, Wake (conditional), Copy IP, DNS/Monitor.
- **Latency history:** `LocalDevice.latencyHistory`, a `@Transient [Double]` buffer (max 20), in memory only; drives the per-device sparklines.

## iOS UI

- **iPad sidebar:** `iPadSidebar` has NETWORK (name, ACTIVE badge, device count, gateway latency) and NAVIGATE sections, reading from the shared `DashboardViewModel` (`connectionTypeIcon`, `networkName`, `gatewayLatency`).
- **Tool navigation:** tool views are pushed via `NavigationLink(value:)` inside `ToolsView`'s `NavigationStack`. Destination views apply toolbar modifiers directly to their body; a second `NavigationStack` inside one silently swallows the push on iOS 18+.

## View-directory docs

Each major view directory has its own `AGENTS.md` (purpose, layout, ViewModel structure, AsyncStream usage, dependencies, accessibility IDs). Read it before modifying views there.

## Agent skills

### Issue tracker

Use GitHub Issues for jbcrane13/NetMonitor-2.0. See `docs/agents/issue-tracker.md`.

### Domain docs

Use a single shared context and the existing architecture records. See `docs/agents/domain.md`.

### Review and merge

Reviewing or merging a pull request: follow `docs/agents/review-workflow.md` (two-axis review, gates on the final code, merge checks). A worker's own review never replaces it.

## Issue Tracking

GitHub Issues via `gh` is the only tracker (no `bd`/beads, no markdown TODO lists). Label every issue with a type, a priority and one status, and use milestones for phases (v2.1, v2.2, Backlog).

- **Type:** `type:bug` · `type:feature` · `type:task` · `type:epic` · `type:chore`
- **Priority:** `priority:critical` · `priority:high` · `priority:medium` · `priority:low` · `priority:backlog`
- **Status:** `status:ready` · `status:in-progress` · `status:blocked` · `status:review`
- **Agent:** `agent:daneel` · `agent:quentin`

```bash
gh issue list --repo jbcrane13/NetMonitor-2.0 --label "status:ready" --state open --json number,title,labels
gh issue create --repo jbcrane13/NetMonitor-2.0 --title "Title" --body-file body.md --label "type:feature,priority:medium,status:ready"
gh issue edit <number> --repo jbcrane13/NetMonitor-2.0 --add-label "status:in-progress" --remove-label "status:ready" --add-assignee "@me"
gh issue close <number> --repo jbcrane13/NetMonitor-2.0 --comment "Done: <summary>"
```

## Git Workflow

Feature worktrees often land on `main` between sessions: `git pull --rebase` before every push, and expect conflicts in `DevicesView.swift` and `ProModeRowView.swift`, which change often. The pre-push hook runs `scripts/check-bonjour-keys.sh` to confirm the Bonjour plist keys are still present.

## Reference Docs

| Document | Location |
|----------|----------|
| Agent Readiness (**read first**) | `docs/agent-readiness/README.md` |
| Architecture rationale | `docs/NETMONITOR-2.0-SHARED-CODEBASE-PLAN.md` |
| Architecture Decision Records | `docs/ADR.md`, `docs/ADR-macOS.md` |
| Companion Protocol (Mac↔iOS) | `docs/Companion-Protocol-API.md` |
| SwiftUI patterns | `docs/SwiftUI Best Practices.md` |
| Testing Lessons Learned | `docs/TESTING-LESSONS-LEARNED.md` |
| Coverage Gates | `docs/testing/coverage-gates.md` |
| Wi-Fi Heatmap PRD | `docs/WiFi-Heatmap-PRD.md` |
| iOS Wi-Fi signal via Shortcuts | `docs/iOS-WiFi-Heatmap-Spec.md` |
| iOS PRD | `docs/NetMonitor iOS Companion - Product Requirements Document.md` |
| macOS PRD | `docs/NetMonitor for macOS - Product Requirements Document.md` |

**Runbooks:** `.factory/skills/run-tests/`, `check-coverage/`, `create-release/`, `fix-lint/`, each with a `SKILL.md`.
