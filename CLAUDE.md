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

# Run tests — see "Test Execution Policy" section below (NEVER run locally)

# Build Swift packages directly
swift build -c debug  # from Packages/NetMonitorCore or Packages/NetworkScanKit
```

**Swift 6, strict concurrency** (`SWIFT_STRICT_CONCURRENCY: complete`). Deployment targets: macOS 15.0, iOS 18.0.

## Monorepo Architecture

```
Packages/
  NetMonitorCore/     # Shared models, service protocols, core services (~10,800 LOC)
  NetworkScanKit/     # Network device discovery engine (~2,400 LOC)
NetMonitor-macOS/     # macOS app target (SwiftData, menu bar, shell-based services)
NetMonitor-iOS/       # iOS app target (companion connection, widget, liquid glass UI)
Tests/                # Unit + UI tests (135 test files across 4 targets)
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
| Wi-Fi signal | CoreWLAN (`CWInterface`) — direct RSSI, noise, channel | Shortcuts "Get Network Details" via `ShortcutsWiFiProvider` (~2s round-trip); `NEHotspotNetwork` fallback (SSID/BSSID only) |
| Heatmap service | `WiFiHeatmapService` (CoreWLAN wrapper) | `IOSHeatmapService` (Shortcuts + NEHotspotNetwork) |

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
- `docs/WiFi-Heatmap-PRD.md` — Wi-Fi Heatmap & Site Survey PRD (macOS + iOS)
- `docs/iOS-WiFi-Heatmap-Spec.md` — iOS Wi-Fi signal acquisition via Shortcuts (technical spec)

## macOS UI Theme Notes

**Dark theme contrast** — macOS views use `MacTheme` (in `MacTheme.swift`) with explicit colors, not system semantic styles. Use `Color.white.opacity(0.7)` for secondary text and `Color.white.opacity(0.5)` for tertiary — SwiftUI's `.secondary`/`.tertiary` are too dim against the dark backgrounds.

**Pro mode table** — `ProModeRowView` defines shared column width constants (`statusWidth`, `ipWidth`, etc.) that `DevicesView.proModeHeaderRow` references. Always keep header and row widths in sync via these constants.

**Scan pipeline** — `DeviceDiscoveryCoordinator.startScan()` runs: ARP → Bonjour → merge → name resolution → vendor lookup → quick port scan (15 common ports) → device type inference → latency (3 pings) → mark offline. `DeviceTypeInferenceService` classifies unknown devices from hostname/services/ports/vendor.

## Shared UI Components (March 2026)

Check for these reusable building blocks before creating new one-off implementations.

### macOS Components

| Component | File | Purpose |
|---|---|---|
| `MiniSparklineView` | `macOS/Views/Components/MiniSparklineView.swift` | Sparkline with threshold coloring, dual overlays. Used by ISPHealthCard, WiFiSignalCard, DeviceCardView, MenuBarPopoverView |
| `CardStateViews` | `macOS/Views/Components/CardStateViews.swift` | Shimmer/skeleton/empty/error states for cards. Use instead of bare `ProgressView()` |
| `QuickJumpSheet` | `macOS/Views/Components/QuickJumpSheet.swift` | ⌘K Spotlight-style device search overlay |
| `DashboardLayout` | `macOS/Views/NetworkDetailView.swift` | 3 breakpoints: compact (<1200pt), standard (1200–1599pt), wide (≥1600pt) |

### Cross-Platform Patterns

| Pattern | Details |
|---|---|
| Tool categories | Both platforms: Diagnostics, Discovery, Monitoring, Actions. macOS: `ToolCategory`, iOS: `IOSToolCategory` (different tool sets) |
| Device quick actions | `quickActionBar` in both DeviceDetailViews: Ping, Scan Ports, Wake (conditional), Copy IP, DNS/Monitor |
| Latency history | `LocalDevice.latencyHistory` — `@Transient [Double]` buffer (max 20), in-memory only, drives per-device sparklines |

### macOS Keyboard Shortcuts

Defined in `KeyboardShortcutsModifier` (ContentView.swift). ⌘1-4 sidebar nav, ⌘R rescan, ⌘K quick jump, ⌘T quick tool.

**Gotcha:** Never chain 5+ `.background { Button... }` modifiers — extract into a `ViewModifier` with a single `.background` containing a `Group`. The Swift type-checker will time out otherwise.

### iPad Sidebar (iOS)

iPad uses `iPadSidebar` with NETWORK (name, ACTIVE badge, device count, gateway latency) and NAVIGATE sections. Reads from shared `DashboardViewModel` (`connectionTypeIcon`, `networkName`, `gatewayLatency`).

### iOS Tool View Navigation (Gotcha)

Tool views are pushed via `NavigationLink(value:)` inside `ToolsView`'s `NavigationStack`. Destination views must NOT wrap their body in a second `NavigationStack` — this creates a nested navigation context that silently swallows the push on iOS 18+. Use toolbar modifiers directly on the view body instead.

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
