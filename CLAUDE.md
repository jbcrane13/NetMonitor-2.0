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

## CRITICAL: Test Execution Policy

**NEVER run `xcodebuild test` on this machine (Mac mini Pro / gateway host).**
Tests MUST run on the Mac mini (secondary node) via SSH:
```bash
# Unit tests (no signing needed):
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-macOS -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:NetMonitor-macOSTests"

# UI tests (need signed build + GUI session):
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-macOS -configuration Debug -destination 'platform=macOS' -only-testing:NetMonitor-macOSUITests"
```
This machine has no display/accessibility session. XCUITests will hang or phantom-launch.
A PreToolUse hook will block `xcodebuild test` locally as a safety net.
