# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build System

The project uses **XcodeGen** to generate the `.xcodeproj` from `project.yml`. Always regenerate after modifying `project.yml`.

```bash
# Regenerate Xcode project
xcodegen generate

# Build macOS target
xcodebuild -scheme NetMonitor-macOS -configuration Debug build

# Build iOS target
xcodebuild -scheme NetMonitor-iOS -configuration Debug build

# Run tests
xcodebuild test -scheme NetMonitor-macOS
xcodebuild test -scheme NetMonitor-iOS

# Build Swift packages directly
swift build -c debug  # from Packages/NetMonitorCore or Packages/NetworkScanKit
```

**Swift 6, strict concurrency** (`SWIFT_STRICT_CONCURRENCY: complete`). Deployment targets: macOS 15.0, iOS 18.0.

## Monorepo Architecture

```
Packages/
  NetMonitorCore/     # Shared models, service protocols, core services (~5,600 LOC)
  NetworkScanKit/     # Network device discovery engine (~2,200 LOC)
NetMonitor-macOS/     # macOS app target (SwiftData, menu bar, shell-based services)
NetMonitor-iOS/       # iOS app target (companion connection, widget, liquid glass UI)
Tests/                # Unit tests (minimal coverage currently)
docs/                 # Architecture docs, ADRs, companion protocol spec
```

**Dependency chain:** macOS/iOS apps → NetMonitorCore → NetworkScanKit

## Package Responsibilities

### NetMonitorCore
Defines all service protocols in `ServiceProtocols.swift` (20+ protocols). Platform-specific targets implement these. Services include: DeviceDiscovery, Ping, PortScanner, DNS, WHOIS, Bonjour, Traceroute, SpeedTest, WakeOnLAN, NetworkMonitor, Notification, MACVendorLookup.

### NetworkScanKit
Multi-phase network scanning pipeline:
1. ARP scan + Bonjour (concurrent)
2. TCP probe + SSDP (concurrent)
3. ICMP latency enrichment (sequential)
4. Reverse DNS resolution (sequential)

Key types: `ScanEngine`, `ScanPipeline`, `ScanContext`, `ScanAccumulator`, `ConnectionBudget`, `ThermalThrottleMonitor`.

## Key Patterns

**Service protocols** — All services are protocol-backed for DI and testability. Protocols in `NetMonitorCore/Services/ServiceProtocols.swift`; implementations in platform targets.

**Observable ViewModels** (iOS) — `@MainActor @Observable final class *ViewModel`. ViewModels live in `NetMonitor-iOS/ViewModels/`. Views contain no business logic.

**AsyncStream** — Long-running operations (ping, port scan, traceroute) return `AsyncStream<T>` for incremental results.

**Concurrency** — All service protocols are `Sendable`. Services that touch state use actors or `@MainActor`. Swift 6 strict concurrency is enforced.

## Platform Differences

| Concern | macOS | iOS |
|---|---|---|
| Ping | Shells to `/sbin/ping` via `ShellCommandRunner` | Network framework / companion |
| ARP scan | Shells to `arp` command | Sysctl BSD API (`ARPCacheScanner`) |
| ICMP | Raw `ICMPSocket` | Via companion or NetworkScanKit |
| Persistence | SwiftData (`NetworkTarget`, `LocalDevice`, `SessionRecord`) | `AppSettings` + `TargetManager` |
| UI theme | Standard system appearance | Liquid glass (`Theme`, `GlassCard`, `GlassButton`) |
| Background | — | `BGTaskScheduler` |
| Mac link | Advertises `_netmon._tcp` on port 8849 | Discovers and connects via `MacConnectionService` |

## Mac–iOS Companion Protocol

Bonjour service type `_netmon._tcp`, port 8849, newline-delimited JSON over `NWConnection`. Spec: `docs/Companion-Protocol-API.md`.

Message types: `statusUpdate`, `deviceListRequest/Response`, `scanRequest/Response`, `commandRequest/Response`.

`CompanionMessage` wire format is defined in NetMonitorCore to keep both sides in sync.

## Naming Conventions

- Views: `*View.swift`
- ViewModels: `*ViewModel.swift`
- Services: `*Service.swift`
- Protocols: `*ServiceProtocol` (defined in `ServiceProtocols.swift`)
- Accessibility IDs: `{screen}_{element}_{descriptor}` (e.g., `dashboard_device_card_192.168.1.1`)

## AGENTS.md Files

Each major view directory contains an `AGENTS.md` with purpose, sub-directory layout, ViewModel structure, AsyncStream usage patterns, dependencies, and accessibility identifier conventions. Check these before modifying views.

## Key Enums (Enums.swift)

`DeviceType`, `StatusType`, `ConnectionType`, `ToolType`, `TargetProtocol`, `DNSRecordType`, `PortScanPreset`, `ScanDisplayPhase`, `SpeedTestPhase`.

## Documentation

- `docs/NETMONITOR-2.0-SHARED-CODEBASE-PLAN.md` — Architecture rationale and goals
- `docs/Companion-Protocol-API.md` — Mac–iOS wire protocol spec
- `docs/ADR.md` — Architecture Decision Records
- `docs/SwiftUI Best Practices.md` — UI patterns and conventions

## macOS UI Theme Notes

**Dark theme contrast** — macOS views use `MacTheme` (in `MacTheme.swift`) with explicit colors, not system semantic styles. Use `Color.white.opacity(0.7)` for secondary text and `Color.white.opacity(0.5)` for tertiary — SwiftUI's `.secondary`/`.tertiary` are too dim against the dark backgrounds.

**Pro mode table** — `ProModeRowView` defines shared column width constants (`statusWidth`, `ipWidth`, etc.) that `DevicesView.proModeHeaderRow` references. Always keep header and row widths in sync via these constants.

**Scan pipeline** — `DeviceDiscoveryCoordinator.startScan()` runs: ARP → Bonjour → merge → name resolution → vendor lookup → quick port scan (15 common ports) → device type inference → latency (3 pings) → mark offline. `DeviceTypeInferenceService` classifies unknown devices from hostname/services/ports/vendor.

## UI Enhancement Components (March 2026)

The following shared components and patterns were introduced during the UI polish pass. These are reusable building blocks — check for them before creating new one-off implementations.

### Shared Components (macOS)

**MiniSparklineView** (`NetMonitor-macOS/Views/Components/MiniSparklineView.swift`) — Reusable sparkline wrapper around `HistorySparkline` (from NetMonitorCore). Renders a dark recessed container with Catmull-Rom spline. Supports threshold-based coloring via `thresholdColor: ((Double) -> Color)?`, dual data overlays, configurable height/pulse/corner radius. Used by ISPHealthCard (dual-overlay latency), WiFiSignalCard (RSSI history), DeviceCardView (per-device latency), and MenuBarPopoverView (gateway latency).

**CardStateViews** (`NetMonitor-macOS/Views/Components/CardStateViews.swift`) — Loading/empty/error state views for dashboard cards. Includes `ShimmerModifier`, `SkeletonBar`, `SkeletonCircle`, `CardLoadingSkeleton(showChart:lineCount:)`, `CardEmptyState(icon:title:subtitle:)`, `CardErrorState`, and `CardStateView` (enum-driven wrapper). Use these instead of bare `ProgressView()` in card loading states.

**QuickJumpSheet** (`NetMonitor-macOS/Views/Components/QuickJumpSheet.swift`) — ⌘K Spotlight-style device search overlay. Filters `LocalDevice` by name, IP, vendor, hostname. Presented as a `.sheet` from ContentView.

### Tool Categories

Both platforms now group tools into categories: Diagnostics, Discovery, Monitoring, Actions.

- macOS: `ToolCategory` enum in `NetMonitor-macOS/Views/ToolsView.swift`
- iOS: `IOSToolCategory` enum in `NetMonitor-iOS/Views/Tools/ToolsView.swift` (note: slightly different tool sets per platform — iOS includes Network Monitor, Room Scanner, Web Browser)

### Sortable Pro Mode Columns (macOS DevicesView)

`DevicesView` has `sortOrder: DeviceSortOrder` and `sortAscending: Bool` state. The `sortableHeader()` helper renders clickable column headers with directional chevrons. Sort cases: `lastSeen`, `name`, `ipAddress`, `status`, `vendor`, `latency`. Last-seen defaults descending; all others default ascending on first click.

### Device Quick Actions

Both macOS `DeviceDetailView` and iOS `DeviceDetailView` include a `quickActionBar` between the header card and network info section. Actions: Ping, Scan Ports, Wake (conditional on MAC address), Copy IP, and DNS/Monitor depending on platform.

### Latency History on LocalDevice

`LocalDevice.latencyHistory` is a `@Transient` `[Double]` buffer (max 20 samples) populated by `updateLatency()`. Not persisted to SwiftData — in-memory only, resets on app restart. Used by `DeviceCardView` to show per-device sparklines.

### Responsive Dashboard Layout (macOS NetworkDetailView)

`NetworkDetailView` uses a `DashboardLayout` enum with three breakpoints: `.compact` (< 1200pt, single-column scroll), `.standard` (1200–1599pt, original 2-column), `.wide` (≥ 1600pt, 3-column with ISP/gauge stacked left). The `diagnosticsStack(gap:)` helper is shared across all three layouts.

### Menu Bar Popover Sections (macOS)

`MenuBarPopoverView` now includes: header → connection status → network stats → **gateway latency sparkline** → **quick actions (Scan/Ping/Speed)** → **problem devices (offline or >100ms)** → target list → footer. The sparkline uses `MiniSparklineView`; problem devices are capped at 3.

### Keyboard Shortcuts (macOS)

Defined in `KeyboardShortcutsModifier` (private struct in `ContentView.swift`). All shortcuts are grouped in a single hidden `.background` to avoid Swift type-checker timeouts from long modifier chains.

| Shortcut | Action |
|---|---|
| ⌘1 | Jump to active network dashboard |
| ⌘2 | Devices list |
| ⌘3 | Tools |
| ⌘4 | Settings |
| ⌘R | Rescan network |
| ⌘K | Quick jump to device (search overlay) |
| ⌘T | Quick tool launch |

**Important pattern note:** Never chain 5+ `.background { Button... }` modifiers on a single view — extract into a `ViewModifier` with a single `.background` containing a `Group` of hidden buttons. The Swift type-checker will time out otherwise.

### iPad Sidebar Polish (iOS ContentView)

iPad `sizeClass == .regular` uses a structured `iPadSidebar` with two sections: NETWORK (shows active network name, ACTIVE badge, device count, gateway latency with threshold coloring) and NAVIGATE (tab rows with accent selection indicator bar). The sidebar reads from a shared `DashboardViewModel` instance for live network status. Helper properties added to `DashboardViewModel`: `connectionTypeIcon`, `networkName`, `gatewayLatency`.

## Git Workflow Note

Feature worktrees frequently land on `main` between sessions. Always `git pull --rebase` before pushing. Expect merge conflicts in `DevicesView.swift` and `ProModeRowView.swift` which are actively evolving.

## CRITICAL: Test Execution Policy

**NEVER run `xcodebuild test` on this machine (Mac mini Pro / gateway host).**
Tests MUST run on the Mac mini (secondary node) via SSH:
```bash
# Unit tests (no signing needed):
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-macOS -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:NetMonitor-macOSTests"

# UI tests (need signed build + GUI session):
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-macOS -configuration Debug -destination 'platform=macOS' -only-testing:NetMonitor-macOSUITests"
```
This machine has no display/accessibility session. XCUITests will hang or phantom-launch.
A PreToolUse hook will block `xcodebuild test` locally as a safety net.
