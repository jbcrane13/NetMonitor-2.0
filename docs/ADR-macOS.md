# Architecture Decision Records — NetMonitor macOS

A running log of significant architecture and design decisions. Both Daneel (OpenClaw) and Claude Code sessions should consult this before making structural changes, and append new entries when decisions are made.

**Format:** Date → Decision → Context → Consequences

---

## ADR-001: MVVM with SwiftUI on macOS 15+
**Date:** 2026-02-09  
**Status:** Active  
**Decision:** MVVM architecture with SwiftUI, targeting macOS 15.0+ (Sequoia).  
**Context:** Modern macOS app with SwiftData persistence, real-time monitoring, and companion app communication.  
**Consequences:**
- ViewModels are `@MainActor @Observable` classes
- Services use `actor` isolation or `@MainActor` depending on threading needs
- SwiftData `@Model` for persistence (NetworkTarget, TargetMeasurement, LocalDevice, SessionRecord)
- Minimum macOS 15 allows use of latest SwiftUI and SwiftData APIs

---

## ADR-002: Swift 6 with async/await and Actors
**Date:** 2026-02-09  
**Status:** Active  
**Decision:** Swift 6 language mode with strict concurrency checking.  
**Context:** Same reasoning as iOS companion — prevent data races, enforce isolation at compile time.  
**Consequences:**
- `SWIFT_STRICT_CONCURRENCY: complete`
- Actor-isolated services for concurrent network operations
- All cross-isolation types must be Sendable

---

## ADR-003: ICMP ping on macOS (vs TCP on iOS)
**Date:** 2026-02-10  
**Status:** Active  
**Decision:** macOS uses real ICMP ping via `ICMPSocket` + `ProcessPingService` (shell ping). iOS uses TCP connect probes.  
**Context:** macOS has raw socket access for ICMP. iOS doesn't without special entitlements. macOS is the "monitoring hub" so accurate ICMP RTT matters.  
**Consequences:**
- `ICMPSocket.swift` wraps low-level ICMP
- `ProcessPingService.swift` uses `/sbin/ping` via shell as fallback
- Cross-platform ping data uses common format but different underlying measurement

---

## ADR-004: NetMonitorShared Swift package for companion protocol
**Date:** 2026-02-10  
**Status:** Active  
**Decision:** Shared SPM package (`NetMonitorShared/`) for code shared between macOS and iOS apps.  
**Context:** Companion protocol messages, common types need to be identical on both sides.  
**Consequences:**
- `CompanionMessage.swift` in shared package
- Both apps import `NetMonitorShared`
- 2.0 goal: expand shared package to include more core services

---

## ADR-005: Bonjour-based companion discovery
**Date:** 2026-02-10  
**Status:** Active  
**Decision:** Use Bonjour (`_netmon._tcp`) for automatic discovery between macOS and iOS apps on the same network.  
**Context:** Zero-configuration networking. User doesn't need to enter IP addresses.  
**Consequences:**
- `CompanionService` advertises/browses on macOS
- `MacConnectionService` connects on iOS
- Heartbeat every 15s, reconnect after 5s
- Requires same LAN (no WAN support in v1)

---

## ADR-006: Menu bar integration
**Date:** 2026-02-10  
**Status:** Active  
**Decision:** Menu bar popover for quick status without opening the main window.  
**Context:** Network monitoring is a "glance at it" use case. Menu bar provides ambient awareness.  
**Consequences:**
- `MenuBarController` manages NSStatusItem
- `MenuBarPopoverView` shows quick stats
- Keyboard shortcuts via `MenuBarCommands`

---

## ADR-007: ARP + Bonjour + MAC vendor for device discovery
**Date:** 2026-02-12  
**Status:** Active  
**Decision:** Three-source device discovery: ARP scanning, Bonjour browsing, and MAC vendor lookup.  
**Context:** Comprehensive device identification requires multiple discovery mechanisms.  
**Consequences:**
- `ARPScannerService` for L2 discovery
- `BonjourDiscoveryService` for service-advertising devices
- `MACVendorLookupService` for manufacturer identification
- `DeviceDiscoveryCoordinator` unifies results

---

## ADR-008: App Store distribution
**Date:** 2026-02-12  
**Status:** Active  
**Decision:** Distribute via Mac App Store. App Store name: "NetMonitor Pro".  
**Context:** Reach + trust. Individual developer account (John Crane, 32XZRDTGK3).  
**Consequences:**
- Bundle ID: `com.netmonitor.NetMonitor`
- Mac App Store ID: 6759060882
- Pricing: $9.99
- Must wrap `#Preview` in `#if DEBUG` for App Store validation
- `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities"`

---

## ADR-009: 2.0 shared codebase goal
**Date:** 2026-02-14  
**Status:** Planned  
**Decision:** Expand `NetMonitorShared` into a full shared foundation for both macOS and iOS. Move models, core services, wire protocols, and network utilities into the shared package.  
**Context:** iOS and macOS codebases diverged during independent development, causing duplicated-code-divergence bugs. macOS `2.0-refactor` branch has initial analysis.  
**Consequences:**
- macOS `2.0-refactor` branch has `ARCHITECTURE-REVIEW.md` and `REFACTORING-ROADMAP.md`
- iOS imports shared package via SPM
- Platform-specific views and services stay in each repo
- Major refactor — needs coordinated effort

---

*To add a new ADR: append with the next number, include date, status, decision, context, and consequences.*
