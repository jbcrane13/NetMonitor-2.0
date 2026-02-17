# NetMonitor 2.0 — Shared Codebase Migration Plan

**Date:** February 16, 2026
**Author:** Daneel (R. Daneel Olivaw)
**Status:** DRAFT — Pending review by Gemini & Codex
**Branch:** `2.0-refactor` (macOS), new `2.0-shared` (iOS)

---

## 1. Executive Summary

NetMonitor macOS and iOS share ~70% of their business logic, but the code is copy-pasted and has diverged. This caused the exact bugs we fought in 1.0: CompanionMessage wire format mismatch, Bonjour discovery differences, TracerouteService doing different things on each platform.

**The fix:** Expand `NetMonitorShared` into a proper multi-platform Swift package containing all shared models, protocols, and services. Both apps import it and add only platform-specific UI and OS-level quirks.

**Expected outcomes:**
- Bug fix once → fixes both platforms
- ~40% reduction in total combined LOC
- Faster feature parity between platforms
- Cleaner architecture for future contributors (or AI agents)

---

## 2. Current State

### 2.1 What Exists Today

| Component | macOS | iOS | Status |
|-----------|-------|-----|--------|
| **NetMonitorShared** (Swift Package) | ✅ Used | ❌ Not used | Contains only `CompanionMessage` (247 LOC) + `Enums` (31 LOC) |
| **NetworkScanKit** (Swift Package) | ❌ Not used | ✅ Used | iOS-only: `ConnectionBudget`, `ScanAccumulator`, `ScanPipeline`, `ThermalThrottleMonitor`, etc. |
| **Total Swift files** | 76 (~11,391 LOC) | ~60 (~8,500 LOC) | Significant overlap in services |

### 2.2 Service-by-Service Comparison

| Service | macOS LOC | iOS LOC | Divergence | Shareable? |
|---------|-----------|---------|------------|------------|
| **PingService** | 95 (ProcessPingService, shells out) | 208 (NWConnection TCP probes) | **High** — fundamentally different approach | ✅ Via protocol + platform impls |
| **TracerouteService** | 371 (POSIX sockets) | 367 (NWConnection) | **Medium** — same algorithm, different transport | ✅ Via protocol + platform impls |
| **BonjourDiscoveryService** | 521 | 296 | **Medium** — macOS has more features | ✅ Shared protocol, platform impls |
| **PortScanService** | 161 | 137 | **Low** — near-identical | ✅ Direct share |
| **SpeedTestService** | 247 | 288 | **Low** — same approach | ✅ Direct share (take iOS version) |
| **WakeOnLANService** | 166 | 144 | **Low** — near-identical | ✅ Direct share |
| **MACVendorLookupService** | 298 | 66 | **High** — macOS has embedded DB | ⚠️ Take macOS version, share |
| **CompanionMessage** | 247 (shared pkg) | 205 (app) | **Medium** — diverged, caused bugs | ✅ Already in shared (iOS must adopt) |
| **DeviceDiscovery** | 521 (Coordinator) | ~800 (Service + scan kit) | **High** — completely different architecture | ⚠️ Shared protocol only |
| **NetworkMonitorService** | ~150 | ~150 | **Low** | ✅ Direct share |

### 2.3 Model Type Comparison

| Type | macOS | iOS | Notes |
|------|-------|-----|-------|
| `PingResult` | Custom struct | `ToolModels.PingResult` | Different fields |
| `PingStatistics` | N/A (inline) | `ToolModels.PingStatistics` | iOS has dedicated type |
| `TracerouteHop` | Custom struct | `ToolModels.TracerouteHop` | Similar structure |
| `PortScanResult` | Custom struct | `ToolModels.PortScanResult` | Nearly identical |
| `BonjourService` | Custom struct | `ToolModels.BonjourService` | Similar but diverged |
| `DNSRecord/QueryResult` | N/A | `ToolModels` | iOS-only tool |
| `WHOISResult` | N/A | `ToolModels` | iOS-only tool |
| `CompanionMessage` | In `NetMonitorShared` | In app Models/ | Must unify |
| `LocalDevice` | `@Model` (SwiftData) | N/A | macOS persistence |
| `DiscoveredDevice` | N/A | In `NetworkScanKit` | iOS scan result |
| `NetworkTarget` | `@Model` (SwiftData) | `MonitoringTarget` | Platform-specific persistence |

---

## 3. Architecture

### 3.1 Target Package Structure

```
NetMonitorShared/
├── Package.swift                          # platforms: [.macOS(.v15), .iOS(.v18)]
├── Sources/
│   └── NetMonitorShared/
│       ├── Models/
│       │   ├── PingResult.swift           # Unified ping result + statistics
│       │   ├── TracerouteHop.swift        # Shared hop model
│       │   ├── PortScanResult.swift       # Shared port scan result
│       │   ├── BonjourServiceModel.swift  # Shared Bonjour service model
│       │   ├── NetworkStatus.swift        # Connection state, WiFi band, etc.
│       │   ├── SpeedTestResult.swift      # Speed test data model
│       │   └── WakeOnLANResult.swift      # WOL result model
│       │
│       ├── Protocol/
│       │   ├── CompanionMessage.swift     # Wire format (already here)
│       │   ├── PingServiceProtocol.swift  # Platform-agnostic ping interface
│       │   ├── TracerouteServiceProtocol.swift
│       │   ├── PortScanServiceProtocol.swift
│       │   ├── BonjourServiceProtocol.swift
│       │   ├── SpeedTestServiceProtocol.swift
│       │   └── WakeOnLANServiceProtocol.swift
│       │
│       ├── Services/
│       │   ├── PortScanService.swift      # Shared impl (NWConnection, works everywhere)
│       │   ├── SpeedTestService.swift     # Shared impl
│       │   ├── WakeOnLANService.swift     # Shared impl (raw UDP socket)
│       │   ├── MACVendorLookupService.swift  # Shared impl (network API + optional embedded DB)
│       │   └── NetworkMonitorService.swift   # Shared NWPathMonitor wrapper
│       │
│       ├── Common/
│       │   ├── Enums.swift               # Already here
│       │   ├── IPv4Helpers.swift          # Subnet math, IP parsing
│       │   └── ServiceUtilities.swift     # Shared utility functions
│       │
│       └── ScanKit/                       # Promoted from iOS NetworkScanKit
│           ├── ConnectionBudget.swift
│           ├── ScanAccumulator.swift
│           ├── ScanPipeline.swift
│           ├── ThermalThrottleMonitor.swift
│           ├── DeviceNameResolver.swift
│           └── ScanContext.swift
│
└── Tests/
    └── NetMonitorSharedTests/
        ├── PingResultTests.swift
        ├── PortScanServiceTests.swift
        ├── CompanionMessageTests.swift
        └── ConnectionBudgetTests.swift
```

### 3.2 What Each App Keeps

**macOS app retains:**
- `ProcessPingService` (shells out to `/sbin/ping` for real ICMP)
- `TracerouteService` (POSIX raw sockets, App Sandbox compatible)
- `ARPScannerService` (shells out to `arp`, macOS-only)
- `DeviceDiscoveryCoordinator` (SwiftData integration, macOS scan flow)
- `ICMPSocket` / `ICMPMonitorService` (raw sockets)
- All SwiftUI views, view models, navigation
- `ShellCommandRunner` (macOS-only)
- SwiftData models (`NetworkTarget`, `LocalDevice`, `SessionRecord`)

**iOS app retains:**
- `PingService` (NWConnection TCP connect probes)
- `TracerouteService` (NWConnection-based)
- `ARPCacheScanner` (sysctl BSD API, iOS-only)
- `DeviceDiscoveryService` (iOS scan flow with ARP + TCP + Bonjour phases)
- `WiFiInfoService` (CoreLocation + NEHotspotNetwork)
- `DNSLookupService`, `WHOISService` (iOS-only tools)
- `GatewayService`, `PublicIPService` (iOS-only)
- All SwiftUI views, view models, navigation
- `BackgroundTaskService` (BGTaskScheduler)

### 3.3 Protocol Pattern for Platform-Divergent Services

```swift
// In NetMonitorShared/Protocol/PingServiceProtocol.swift
public protocol PingServiceProtocol: Sendable {
    func ping(host: String, count: Int, timeout: TimeInterval) async -> AsyncStream<PingResult>
    func stop() async
}

// macOS app provides:
extension ProcessPingService: PingServiceProtocol { ... }

// iOS app provides:
extension PingService: PingServiceProtocol { ... }
```

This pattern applies to: `PingService`, `TracerouteService`, `BonjourDiscoveryService`, and `DeviceDiscoveryService`.

---

## 4. Migration Phases

### Phase 1: Foundation (Models + Protocols) — ~2 days
**Goal:** Get both apps compiling against `NetMonitorShared` with zero behavior change.

1. **Expand `NetMonitorShared` models:**
   - Add `PingResult`, `PingStatistics`, `TracerouteHop`, `PortScanResult`, `BonjourServiceModel`, `SpeedTestResult`, `WakeOnLANResult`
   - Unify field names (use iOS naming as baseline — it's more recent)
   - All types: `public struct`, `Sendable`, `Identifiable` where appropriate

2. **Add service protocols:**
   - `PingServiceProtocol`, `TracerouteServiceProtocol`, `PortScanServiceProtocol`
   - `BonjourServiceProtocol`, `SpeedTestServiceProtocol`, `WakeOnLANServiceProtocol`

3. **Unify `CompanionMessage`:**
   - iOS adopts the shared package version (delete local copy)
   - Ensure wire format is identical (length-prefixed JSON)

4. **Add `NetMonitorShared` dependency to iOS project:**
   - Local package reference (same monorepo pattern or git submodule)

5. **Both apps compile with shared models:**
   - `typealias` bridge where names differ during transition
   - No behavior changes yet

**Validation:** Both apps build. All existing tests pass. No runtime changes.

### Phase 2: Direct-Share Services — ~2 days
**Goal:** Move services that work identically on both platforms into the shared package.

1. **PortScanService** → `NetMonitorShared/Services/`
   - Both use NWConnection TCP connect. Nearly identical code.
   - Take iOS version (cleaner), add any macOS-specific features.

2. **SpeedTestService** → `NetMonitorShared/Services/`
   - Both use URLSession download/upload measurement. Same approach.
   - Take iOS version, port macOS extras.

3. **WakeOnLANService** → `NetMonitorShared/Services/`
   - Both construct raw UDP magic packets. Near-identical.

4. **NetworkMonitorService** → `NetMonitorShared/Services/`
   - Both wrap NWPathMonitor. Trivial to share.

5. **MACVendorLookupService** → `NetMonitorShared/Services/`
   - Merge: macOS embedded DB + iOS network API fallback.

6. **Delete duplicated files** from each app.

**Validation:** Both apps build. Services produce identical results. Run tool-by-tool QA on both platforms.

### Phase 3: ScanKit Promotion — ~1 day
**Goal:** Move iOS's `NetworkScanKit` into `NetMonitorShared/ScanKit/` so macOS can use it.

1. Move `ConnectionBudget`, `ScanAccumulator`, `ScanPipeline`, `ThermalThrottleMonitor`, `DeviceNameResolver`, `ScanContext`, `IPv4Helpers` into shared.
2. iOS: Remove `NetworkScanKit` local package, import from `NetMonitorShared`.
3. macOS: Optionally adopt `ConnectionBudget` in `DeviceDiscoveryCoordinator`.
4. Update `DiscoveredDevice` to live in shared (platform-neutral subset).

**Validation:** iOS scan produces same results. macOS builds. No regressions.

### Phase 4: Protocol-Based Services — ~3 days
**Goal:** Define shared protocols for platform-divergent services, implement per-platform.

1. **PingService:**
   - Protocol in shared, macOS `ProcessPingService` conforms, iOS `PingService` conforms.
   - Shared `PingResult` model already in place from Phase 1.

2. **TracerouteService:**
   - Protocol in shared. Both implementations stay in their apps.
   - Very similar algorithm — potential to extract ~60% into a shared base.

3. **BonjourDiscoveryService:**
   - Protocol in shared. Implementations stay platform-specific.
   - Shared `BonjourServiceModel` for results.

4. **Wire up DI:**
   - Both apps inject platform-specific implementations via protocols.
   - Views/ViewModels depend on protocols, not concrete types.

**Validation:** All tools work on both platforms. Protocol conformance tests in shared package.

### Phase 5: Cleanup & Testing — ~2 days
**Goal:** Remove dead code, add shared tests, document the architecture.

1. Delete all orphaned files from both apps.
2. Add unit tests to `NetMonitorSharedTests`:
   - Model encoding/decoding (especially `CompanionMessage` wire format)
   - `ConnectionBudget` fairness and limits
   - `PortScanService`, `WakeOnLANService` basic behavior
   - Protocol conformance validation
3. Update `ARCHITECTURE-REVIEW.md` in both repos.
4. Add `docs/ADR.md` entry for the shared codebase decision.
5. Update `README.md` with package dependency diagram.

**Validation:** Test coverage >60% on shared package. Clean builds on both platforms. ADR recorded.

---

## 5. Repo Strategy

### Option A: Git Submodule (Recommended)
```
NetMonitor/          (macOS app)
├── NetMonitorShared/   ← git submodule → github.com/…/NetMonitorShared
└── ...

NetMonitor-iOS/      (iOS app)
├── NetMonitorShared/   ← git submodule → github.com/…/NetMonitorShared
└── ...
```

**Pros:** Single source of truth, independent versioning, works with both Xcode and SPM.
**Cons:** Submodule workflow is clunkier. Must remember to push submodule changes.

### Option B: Local Package Reference (Simpler)
Both repos reference `../NetMonitorShared` as a local SPM dependency during development. CI uses a pinned git tag.

**Pros:** Simplest development workflow. No submodule overhead.
**Cons:** Requires both repos checked out side-by-side. CI needs separate setup.

### Option C: Monorepo
Move both apps into a single repo with the shared package at the root.

**Pros:** Atomic changes across both platforms. Single PR for shared + app changes.
**Cons:** Large repo. Different CI triggers. Bigger blast radius per commit.

**Recommendation:** Start with **Option B** (local package reference) for speed. Migrate to **Option A** (submodule) once the package stabilizes post-Phase 2. Consider **Option C** only if we add more platforms (watchOS, tvOS).

---

## 6. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **Model unification breaks serialization** | Medium | High | Wire format tests for CompanionMessage. Never change Codable keys. |
| **Platform #if sprawl** | Medium | Medium | Prefer protocols over `#if os()`. Use `#if` only for import differences. |
| **Merge conflicts during migration** | High | Low | Sequential phases. One service at a time. Feature branch per phase. |
| **Performance regression on iOS scan** | Low | High | Benchmark device count + scan time before/after each phase. |
| **Breaking macOS SwiftData integration** | Low | Medium | macOS keeps its own model layer. Shared models are plain structs. |
| **Agent parallelism conflicts** | Medium | Medium | One agent per phase. No parallel modifications to shared package. |

---

## 7. Success Metrics

- [ ] Both apps compile against `NetMonitorShared` with zero `#if os()` in shared code
- [ ] `CompanionMessage` is imported from shared on both platforms (zero local copies)
- [ ] ≥5 services fully shared (PortScan, SpeedTest, WOL, NetworkMonitor, MACVendor)
- [ ] ≥4 service protocols defined for platform-divergent services
- [ ] Shared package test coverage >60%
- [ ] iOS device count ≥30 (no regression from current 34)
- [ ] macOS companion pairing works cross-platform
- [ ] Total combined LOC reduced by ≥25%

---

## 8. Timeline Estimate

| Phase | Duration | Dependency |
|-------|----------|------------|
| Phase 1: Foundation | 2 days | None |
| Phase 2: Direct-Share Services | 2 days | Phase 1 |
| Phase 3: ScanKit Promotion | 1 day | Phase 1 |
| Phase 4: Protocol-Based Services | 3 days | Phases 1-3 |
| Phase 5: Cleanup & Testing | 2 days | Phase 4 |
| **Total** | **~10 days** | |

Phases 2 and 3 can run in parallel after Phase 1.

---

## 9. Open Questions

1. **Monorepo vs multi-repo?** — Recommendation above is multi-repo with local refs. Blake to decide.
2. **Should `NetworkScanKit` keep its name or merge into `NetMonitorShared/ScanKit`?** — Recommend merge.
3. **SwiftData models stay per-app or extract shared schemas?** — Recommend per-app (persistence is inherently platform-specific).
4. **iOS `DNSLookupService` and `WHOISService` — worth sharing?** — macOS doesn't have these tools yet. Add to shared when macOS gains them.
5. **Minimum deployment targets** — Package currently says `.macOS(.v15), .iOS(.v18)`. Correct?

---

*This plan is a living document. Update as reviews come in and decisions are made.*
