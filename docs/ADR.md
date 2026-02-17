# Architecture Decision Records — NetMonitor iOS

A running log of significant architecture and design decisions. Both Daneel (OpenClaw) and Claude Code sessions should consult this before making structural changes, and append new entries when decisions are made.

**Format:** Date → Decision → Context → Consequences

---

## ADR-001: XcodeGen for project management
**Date:** 2026-02-09  
**Status:** Active  
**Decision:** Use XcodeGen (`project.yml`) instead of manually maintaining the `.xcodeproj`.  
**Context:** Multiple agents and Blake all modify the project; merge conflicts in `.xcodeproj` are painful.  
**Consequences:**
- Run `xcodegen generate` after any project.yml change
- Build settings like `DEVELOPMENT_TEAM`, `CODE_SIGN_ENTITLEMENTS` must be in `project.yml` or they get wiped on regeneration
- `.xcodeproj` is gitignored (regenerated)

---

## ADR-002: Swift 6 strict concurrency from day one
**Date:** 2026-02-09  
**Status:** Active  
**Decision:** `SWIFT_STRICT_CONCURRENCY: complete` and Swift 6.0 language mode.  
**Context:** Prevents data races; forces explicit isolation decisions upfront rather than retrofitting later.  
**Consequences:**
- All types crossing isolation boundaries must be `Sendable`
- UI-bound services/VMs are `@MainActor @Observable`
- Network-heavy services that need true parallelism use `actor`
- Some `nonisolated(unsafe)` and `@unchecked Sendable` workarounds exist — these should be documented (see ADR beads)

---

## ADR-003: ICMP-primary ping with TCP fallback
**Date:** 2026-02-10 (revised 2026-02-16)
**Status:** Active
**Decision:** PingService uses ICMP echo (`SOCK_DGRAM/IPPROTO_ICMP`) as the primary ping method and falls back to TCP connect probes (ports 443, 80, 22) only when ICMP socket creation fails.
**Context:** Originally TCP-only because iOS raw sockets require special entitlements. However, `SOCK_DGRAM` ICMP sockets are unprivileged and App Store approved — no entitlements needed. ICMP gives accurate sub-millisecond RTT via `ContinuousClock`, whereas TCP handshake timing via NWConnection adds ~70ms of framework overhead.
**Consequences:**
- ICMP latency matches what users expect from `ping` (true network RTT)
- TCP fallback preserves reachability on Simulator and environments where ICMP socket creation fails
- `ICMPSocket` actor manages BSD socket lifecycle with dedicated I/O dispatch queue

---

## ADR-004: NetworkScanKit as local Swift package
**Date:** 2026-02-14  
**Status:** Active  
**Decision:** Extract scan infrastructure into a local SPM package (`Netmonitor/NetworkScanKit/`).  
**Context:** Scan logic (ARP, Bonjour, TCP probe, SSDP, reverse DNS) was tangled inside `DeviceDiscoveryService` (936 lines). Needed composable scan phases for the 2.0 shared-codebase goal.  
**Consequences:**
- `ScanPhase` protocol + `ScanEngine` actor + `ScanPipeline` orchestrator
- Types like `DiscoveredDevice`, `ScanAccumulator`, `ConnectionBudget` moved to package
- App files must `import NetworkScanKit` for moved types
- Package resolves as `XCLocalSwiftPackageReference` in the xcodeproj

---

## ADR-005: ARP cache scanning for device discovery
**Date:** 2026-02-14  
**Status:** Active  
**Decision:** Use UDP probe + BSD sysctl ARP cache read as the primary device discovery mechanism.  
**Context:** Competitive analysis showed ARP scanning finds significantly more devices than TCP probing alone (34 devices vs ~15). It's the technique used by Fing, Net Analyzer, etc.  
**Consequences:**
- BSD routing types defined inline (iOS SDK doesn't export `<net/route.h>`)
- ARP phase runs first, overlapped with Bonjour
- Found devices skip TCP probing (saves NWConnections and heat)

---

## ADR-006: Tiered Bonjour browsing
**Date:** 2026-02-14  
**Status:** Active  
**Decision:** Browse high-yield Bonjour service types (HTTP, SMB, SSH, AirPlay) immediately; defer low-yield types by 3-5 seconds.  
**Context:** Browsing 18 service types simultaneously creates resource pressure during the scan's critical window. Most useful results come from ~6 types.  
**Consequences:**
- Tier 1 (6 types): immediate
- Tier 2 (12 types): delayed 3s
- 30s timeout auto-finishes discovery to prevent hung streams

---

## ADR-007: Generation-based stale callback prevention
**Date:** 2026-02-15  
**Status:** Active  
**Decision:** Use monotonically increasing generation IDs in `BonjourDiscoveryService` (and `BonjourDiscoveryToolViewModel`) to prevent stale NWBrowser callbacks from prior sessions from polluting current results.  
**Context:** Bonjour discovery tool kept breaking because callbacks from cancelled browsers arrived after a new discovery had started. `onTermination` calling `stopDiscovery()` also caused re-entrancy.  
**Consequences:**
- Every browser callback checks `self.generation == gen` before processing
- `onTermination` removed from AsyncStream — teardown is explicit only
- ViewModel uses `runID` to prevent stale tasks from resetting state

---

## ADR-008: ViewModels own services via @State, not singletons
**Date:** 2026-02-09  
**Status:** Active (with exceptions)  
**Decision:** Views create ViewModels via `@State`, ViewModels create services in `init()`. Avoid global singletons where possible.  
**Context:** Testability and lifecycle clarity. Each tool screen manages its own service lifecycle.  
**Consequences:**
- Some services (NetworkMonitorService, WiFiInfoService) are still effectively singletons because they monitor global state
- DI via protocol injection in ViewModel init (e.g., `BonjourDiscoveryToolViewModel(bonjourService:)`)
- Architecture review (2026-02-15) flagged that `DeviceDetailViewModel` needs DI added

---

## ADR-009: Beads for task tracking
**Date:** 2026-02-14  
**Status:** Active  
**Decision:** All work tracked via `beads` (`bd` CLI) — every fix/feature gets a bead, status updates required, IDs in commit messages.  
**Context:** Multiple agents working on the codebase need a shared task tracking system that lives in the repo.  
**Consequences:**
- `.beads/` directory in repo root
- `bd list`, `bd create`, `bd close` workflow
- Dependency chains between beads (blocked-by/blocks)

---

## ADR-010: Architecture review phases (2026-02-15)
**Date:** 2026-02-15  
**Status:** Active  
**Decision:** Four-phase remediation plan from comprehensive architecture review:
- **Phase 1 (P0-P1):** Safety fixes — scanTask assignment, @MainActor on ThemeManager, BackgroundTaskService race, DNSLookupService isolation, ContentView ThemeManager @State
- **Phase 2 (P2):** DI/Protocol cleanup — extract Phase enum, add DI to DeviceDetailViewModel, route MacConnectionService through ViewModels
- **Phase 3 (P2-P3):** Consolidation — centralize UserDefaults keys, extract shared utilities, replace deprecated OSAtomicAdd64, extract pruneExpiredData
- **Phase 4 (P3-P4):** Polish — os.Logger, document unsafe markers, evaluate singletons, re-export NetworkScanKit types, make stop() async, refactor DNS

**Context:** Full services architecture review (324-line `ARCHITECTURE-REVIEW.md`) identified ~3,000 NWConnection churn as primary heat source, threading model issues, and consolidation opportunities.  
**Consequences:**
- 22 beads created with dependency chains
- Phase 1 blocks Phase 2 blocks Phase 3 blocks Phase 4
- Epic beads track phase completion

---

## ADR-011: Build number management
**Date:** 2026-02-15  
**Status:** Active  
**Decision:** `CURRENT_PROJECT_VERSION` in `project.yml` is a baseline; actual build numbers for TestFlight are passed via CLI (`CURRENT_PROJECT_VERSION=N`). Always check ASC API for the latest build number before uploading.  
**Context:** Build numbers must be monotonically increasing on App Store Connect. Multiple agents uploading without checking led to rejected builds.  
**Consequences:**
- Query ASC API before archive: `filter[app]=6759060947&sort=-version&limit=1`
- Pass `CURRENT_PROJECT_VERSION=<next>` on the `xcodebuild archive` CLI
- iOS App ID: 6759060947, macOS App ID: 6759060882

---

## ADR-012: Export compliance and signing in project.yml
**Date:** 2026-02-15  
**Status:** Active  
**Decision:** `DEVELOPMENT_TEAM`, `ITSAppUsesNonExemptEncryption`, and `CODE_SIGN_ENTITLEMENTS` are set in `project.yml` so they survive xcodegen regeneration.  
**Context:** These kept getting wiped every time xcodegen ran, requiring manual re-entry in Xcode.  
**Consequences:**
- `DEVELOPMENT_TEAM: 32XZRDTGK3` at project level (all targets)
- `CODE_SIGN_ENTITLEMENTS: Netmonitor/Netmonitor.entitlements` on main target only (not widget)
- `ITSAppUsesNonExemptEncryption: NO` at project level
- No more "select a development team" errors after regeneration

---

## ADR-013: GatewayService/PublicIPService remain fresh-instance (no singleton)
**Date:** 2026-02-15
**Status:** Active
**Decision:** Keep GatewayService and PublicIPService as fresh instances created via DI defaults in ViewModel `init()`. Do not introduce singletons.
**Context:** Architecture review bead `NetMonitor-iOS-rnx` flagged that GatewayService (5 instantiation sites) and PublicIPService (2 sites) create independent instances that don't share cached results. Evaluation found this is the correct pattern:

- **GatewayService** performs a single LAN TCP connection (<10ms). No caching, no long-lived state. The three ViewModels (Dashboard, Map, Tools) live on separate tabs — only the active tab calls `detectGateway()`. SwiftUI `@State` preserves VM instances across tab switches, so services aren't constantly recreated.
- **PublicIPService** is only used in DashboardViewModel (one ViewModel). Its 5-minute per-instance cache prevents excessive API calls during auto-refresh. BackgroundTaskService correctly uses fresh instances since background tasks have separate lifecycles.
- Services that ARE singletons (`NetworkMonitorService`, `DeviceDiscoveryService`, `MacConnectionService`) hold long-lived NWPathMonitor connections, discovered device lists, or persistent connections — genuinely shared state. Gateway/PublicIP are stateless query services.

**Consequences:**
- Reinforces ADR-008 pattern: ViewModels own services via `@State`, not singletons
- No new shared mutable state introduced
- Negligible duplicate network cost (LAN TCP vs external API with cache)
- Consistent with Phase 1-3 direction of moving away from singletons toward DI

---

## ADR-014: ICMP latency enrichment in scan pipeline
**Date:** 2026-02-16
**Status:** Active
**Decision:** Add `ICMPLatencyPhase` to the `DeviceDiscoveryService` scan pipeline (after TCP+SSDP, before Reverse DNS). ICMP measurements overwrite TCP-based latency for all discovered devices.
**Context:** Scan latency was consistently ~70ms higher than standalone ping tests. Root cause: `DeviceDiscoveryService` built a custom pipeline omitting `ICMPLatencyPhase` (which existed in `ScanPipeline.standard()` but wasn't used). All device latency came from NWConnection TCP handshake timing, which is inflated by framework overhead, dispatch queue congestion (40 hosts x 3 ports = 120 concurrent NWConnections on shared `scanQueue`), and `Date()` wall-clock vs `ContinuousClock` precision. Bead: `NetMonitor-iOS-qbx`.
**Consequences:**
- Pipeline order: ARP+Bonjour → TCP+SSDP → **ICMP Latency** → Reverse DNS
- `ScanAccumulator` gained `allDeviceIPs()` and `replaceLatency()` so ICMP overwrites TCP measurements
- ICMP uses single-socket ping sweep on dedicated serial queue (`icmpQueue`) — no async suspension between reads ensures accurate timing
- Removed broken `identifier` check from `ICMPLatencyPhase.pingSweep()` — `SOCK_DGRAM` ICMP sockets have kernel-remapped identifiers, so the check always failed silently. Sequence-number matching is sufficient since the kernel filters responses per-socket
- TCP latency preserved as fallback when ICMP socket creation fails (e.g., Simulator)
- Adds ~2s to scan time (ICMP collect timeout) but produces accurate latency

---

## ADR-015: Set Target quick action with shared TargetManager
**Date:** 2026-02-16
**Status:** Active
**Decision:** Replace the "Monitor Network" quick action on the Tools tab with a "Set Target" button backed by a `TargetManager` singleton. The selected target pre-fills the input field in Ping, Traceroute, DNS Lookup, Port Scanner, and WHOIS tools.
**Context:** The "Monitor Network" quick action was redundant — it navigated to `NetworkMapView`, which already has its own tab (Map). The space is better used for a target management feature that reduces repetitive typing when investigating a specific host across multiple tools. Blake identified this during 1.0 final polish.
**Consequences:**
- `TargetManager` is `@MainActor @Observable` singleton with `currentTarget` (in-memory, resets on launch) and `savedTargets` (persisted to UserDefaults, max 10)
- `ToolDestination.view` reads `TargetManager.shared.currentTarget` and passes it as `initialHost`/`initialDomain` to each applicable tool view
- `TracerouteToolViewModel` and `WHOISToolViewModel` gained `initialHost`/`initialDomain` init params (Ping, DNS, PortScanner already had them)
- Tools that don't take a host/domain target (Bonjour, Speed Test, Wake on LAN, Web Browser) are unaffected
- "Target Down Alert" and "New Device Detected Alert" removed from Settings (not useful without continuous monitoring)
- Web Browser "Router Admin" bookmark now uses `NetworkUtilities.detectDefaultGateway()` instead of hardcoded `192.168.1.1`

---

## ADR-016: ConnectionBudget deadlock fix and scan-start reset
**Date:** 2026-02-16
**Status:** Active
**Decision:** Fix `ConnectionBudget.release()` to always resume waiters unconditionally, and add a `reset()` call at scan start to reclaim any leaked slots from prior tool usage.
**Context:** Blake reported a reproducible bug: use other tools (ping, port scanner) first, then navigate to network scan for the first time — scan hangs forever, never finds devices. Root cause was a two-part deadlock in `ConnectionBudget`:

1. **Thermal throttle deadlock:** `release()` checked `active < effectiveLimit` before waking waiters. If the device heated up during port scanning, `effectiveLimit` dropped (e.g., 60→30 at `.serious`). Subsequent `release()` calls decremented `active` but refused to wake waiters because `active` was still >= the lowered limit. Waiters were permanently stuck.
2. **`defer { Task { release() } }` slot leaks:** Every acquire/release pair across the codebase (6 call sites) used `defer { Task { await ConnectionBudget.shared.release() } }` — unstructured Tasks for release. When parent tasks are cancelled (e.g., user stops port scanner) or the cooperative pool is saturated, these release Tasks can be delayed or dropped, leaking budget slots.

The scan pipeline uses `withTaskGroup` that waits for ALL phases in a step. If `TCPProbeScanPhase` or `SSDPScanPhase` blocked on `acquire()` waiting for leaked slots, the entire pipeline hung.

**1.0 fix (safe, minimal):**
- `release()`: Removed `active < effectiveLimit` guard — always resumes next waiter when a slot frees
- `reset()`: New method that force-drains all waiters and zeros active count
- `DeviceDiscoveryService.performScan()`: Calls `reset()` at scan start to reclaim leaked slots
- Also fixed `"router"` → `"wifi.router"` SF Symbol (was failing at runtime)

**2.0 fix (proper, requires refactor):**
- Replace `defer { Task { release() } }` pattern with structured concurrency. Each call site should use a helper like `withConnectionSlot { connection in ... }` that guarantees release via `defer { await release() }` in an async context, or uses `withTaskCancellationHandler` to release on cancellation
- Consider making `ConnectionBudget` cancellation-aware: if a task waiting in `acquire()` is cancelled, automatically remove its continuation from the waiters list and don't increment `active`
- Add budget health diagnostics (log warning when active count exceeds threshold for >N seconds)
- Evaluate whether `effectiveLimit` should only affect new `acquire()` calls, never block `release()` from waking waiters (the 1.0 fix already achieves this)

**Consequences:**
- 1.0: Scan always starts with a clean budget — can't be starved by prior tool usage
- 1.0: Slight over-admission possible if reset() fires while tools are still actively using slots (unlikely in practice since scan only starts from user action on a different tab)
- 2.0: Structured `withConnectionSlot` pattern eliminates the leak class entirely

---

## ADR-017: Monorepo with shared SPM packages for 2.0
**Date:** 2026-02-17  
**Status:** Proposed  
**Bead:** NetMonitor-iOS-hib  
**Decision:** Consolidate macOS and iOS apps into a single monorepo with shared Swift Package Manager libraries (`NetMonitorCore`, `NetworkScanKit`), platform-specific app targets, and XcodeGen for project generation.

**Context:**  
NetMonitor exists as two separate repositories — macOS (`~/Projects/NetMonitor`, on App Store as "NetMonitor Pro") and iOS (`~/Projects/NetMonitor-iOS`, 1.0 just submitted). Both apps share ~60% of non-UI code, but the codebases have diverged independently:

- **ICMPSocket** is byte-for-byte identical across both
- **Services** (Traceroute, PortScanner, WOL, SpeedTest, Bonjour, etc.) are 60-95% similar but with different patterns — macOS uses `ContinuationTracker`, shell-based ping, simpler models; iOS uses `ResumeState` actors, ICMP-first ping, `ConnectionBudget`, richer models
- **Models** have diverged naming and raw values (e.g., `ConnectionType.wifi` = `"WiFi"` on macOS vs `"wifi"` on iOS)
- **CompanionMessage** was originally shared via `NetMonitorShared` SPM but iOS copied and evolved it independently
- Bug fixes must be applied twice (e.g., `ConnectionBudget` deadlock fix in ADR-016 only exists on iOS)
- iOS has a complete MVVM architecture with ViewModels, service protocols, and 25+ test files; macOS has logic-in-Views and minimal tests

The 2.0 roadmap goal is: "Shared codebase — expand NetMonitorShared, eliminate cross-platform divergence."

**Alternatives considered:**

1. **Git submodule for shared code:** Rejected — submodule workflows are fragile, version pinning creates sync headaches, and PRs span multiple repos.
2. **Published SPM packages (separate repos):** Rejected — overhead of versioning/publishing for a single-developer project. Local packages in a monorepo give the same modularity with simpler workflows.
3. **Keep separate repos, manually sync:** Rejected — this is the status quo and it's already causing divergence. The ICMPSocket being identical is lucky; most services have drifted.
4. **Multiplatform SwiftUI (single target with `#if os()`):** Rejected — too many View differences (sidebar vs tabs, MenuBar, Widget, macOS Settings panes). Platform targets are cleaner.

**Structure:**
```
NetMonitor-2.0/
├── Packages/
│   ├── NetMonitorCore/      ← shared models, services, utilities
│   └── NetworkScanKit/      ← scan engine (already exists on iOS)
├── NetMonitor-macOS/        ← macOS views, platform services
├── NetMonitor-iOS/          ← iOS views, ViewModels, platform services
├── Tests/
└── project.yml              ← XcodeGen
```

**Key design decisions within this ADR:**
- iOS codebase is the primary source for shared services (newer, better patterns, more tests)
- `ResumeState` (actor-based) replaces `ContinuationTracker` everywhere
- `PingService` uses ICMP socket (iOS approach), not shell-based ping
- `ConnectionType` raw values standardized to lowercase (iOS convention)
- ViewModels remain platform-specific initially; shared business logic lives in services
- WiFi info remains platform-specific (CoreWLAN vs NEHotspotNetwork)
- `CompanionMessage` reunified from `NetMonitorShared` as the single source of truth

**Consequences:**
- All bug fixes to services apply to both platforms automatically
- New features (e.g., WHOIS, DNS Lookup currently iOS-only) become available on macOS "for free"
- macOS app gains: proper MVVM separation, ICMP-based ping, parallel speed test, service protocol DI, `ConnectionBudget` throttling, full test suite
- SwiftData `LocalDevice` model needs schema migration (different field sets between platforms)
- macOS Views require refactoring to work with new model types (biggest effort, ~5-7 days)
- Must preserve existing App Store bundle IDs for continuity
- Old repos archived, not deleted — available for reference/rollback
- Estimated total effort: 3-4 weeks

**Full plan:** `docs/plans/2026-02-17-monorepo-2.0-plan.md`

---

*To add a new ADR: append with the next number, include date, status, decision, context, and consequences. Reference the bead ID if applicable.*
