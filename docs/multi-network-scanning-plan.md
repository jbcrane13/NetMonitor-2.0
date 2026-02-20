# Multi-Network Scanning — Implementation Plan

**Bead:** NM2-d8c  
**Priority:** P1  
**Goal:** Allow users to pick a router/gateway from discovered devices and scan *that* router's network, enabling monitoring of multiple subnets beyond the directly-connected local network.

---

## Current Architecture

### How Scanning Works Today

1. **iOS:** `DeviceDiscoveryService` → `ScanEngine` → `ScanPipeline` (ARP → Bonjour → TCP Probe → SSDP → ICMP → Reverse DNS)
2. **macOS:** `DeviceDiscoveryCoordinator` → `ARPScannerService` + `BonjourDiscoveryService` (simpler, no ScanEngine)
3. **Network detection:** `GatewayService.detectGateway()` uses `NetworkUtilities.detectDefaultGateway()` to find the local router
4. **Subnet scoping:** `ScanContext.subnetFilter` limits results to the current /24 subnet
5. **Target system (iOS):** `TargetManager` stores a target IP for pre-filling tool inputs — but does NOT affect which network is scanned

### Key Constraint
- **ARP scanning only works on the directly-connected network** — you can't ARP for devices on a remote subnet
- **TCP/ICMP probes work across subnets** if there's a route (e.g., through a VPN or secondary router on the same LAN)
- For truly remote subnets (behind a NAT router), scanning requires either: (a) the router exposes an API (UPnP/SSDP), (b) a companion agent on that network, or (c) sequential hop-based discovery

---

## Design

### Concept: "Network Profiles"

A **Network Profile** represents a scannable network defined by:
- **Gateway IP** — the router for this network
- **Subnet** — CIDR range (e.g., `192.168.2.0/24`)
- **Name** — user-editable label (auto-detected from SSID or router hostname)
- **Discovery method** — how we found this network (auto-detected, manual, companion)
- **Scan strategy** — which phases work for this network (local: full pipeline, remote: TCP+ICMP only)

### User Flow

1. **Auto-detect current network** — happens on launch (existing behavior)
2. **"Add Network" button** on Dashboard/Network Map:
   - Option A: **Pick from discovered routers** — if a scan found devices that look like routers (port 80/443 open, UPnP, gateway MAC vendor), offer them as scannable networks
   - Option B: **Manual entry** — user types gateway IP + subnet CIDR
   - Option C: **Companion Protocol** — macOS companion reports its network info (already partially built)
3. **Network switcher** — persistent UI element (segmented control or dropdown) to switch between known networks
4. **Scan selected network** — pipeline adapts based on reachability:
   - **Local network** (same subnet): full pipeline (ARP + Bonjour + TCP + SSDP + ICMP + DNS)
   - **Routable remote** (different subnet, reachable): TCP Probe + ICMP + Reverse DNS (no ARP/Bonjour)
   - **Unreachable**: show error, suggest Companion Protocol

### Architecture Changes

```
┌─────────────────────────────────────────────────┐
│                NetworkProfileManager             │
│  - profiles: [NetworkProfile]                    │
│  - activeProfile: NetworkProfile                 │
│  - addProfile / removeProfile / switchProfile    │
│  - persist to UserDefaults/SwiftData             │
└────────────────────┬────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│              ScanContext (enhanced)               │
│  + networkProfile: NetworkProfile                │
│  + scanStrategy: ScanStrategy (.full / .remote)  │
└────────────────────┬────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│         ScanPipeline.forStrategy()               │
│  .full → standard 4-step pipeline                │
│  .remote → TCP Probe + ICMP + DNS only           │
└─────────────────────────────────────────────────┘
```

---

## Task Breakdown

### Phase 1: Core Model & Manager (Shared)

**NM2-d8c.1 — NetworkProfile model and manager**
- Create `NetworkProfile` struct in `NetMonitorCore`:
  ```swift
  public struct NetworkProfile: Identifiable, Codable, Sendable {
      public let id: UUID
      public var name: String
      public var gatewayIP: String
      public var subnet: String        // CIDR notation: "192.168.2.0/24"
      public var subnetMask: String    // "255.255.255.0"
      public var isLocal: Bool         // auto-detected as current network
      public var discoveryMethod: DiscoveryMethod  // .auto, .manual, .companion
      public var lastScanned: Date?
      public var deviceCount: Int?
  }
  ```
- Create `NetworkProfileManager` (@Observable, @MainActor):
  - `profiles: [NetworkProfile]`
  - `activeProfile: NetworkProfile?`
  - Auto-detects current network on init
  - Persists profiles to UserDefaults (JSON encoded)
  - `addProfile(gateway:subnet:name:)` — validates and adds
  - `removeProfile(id:)` — removes (can't remove local)
  - `switchProfile(id:)` — sets active, triggers re-scan notification
  - `detectLocalNetwork()` — creates/updates the local profile from GatewayService
- **Tests:** Unit tests for profile CRUD, persistence, local detection

### Phase 2: Scan Strategy Adaptation (NetworkScanKit)

**NM2-d8c.2 — ScanStrategy and pipeline adaptation**
- Add `ScanStrategy` enum to NetworkScanKit:
  ```swift
  public enum ScanStrategy: Sendable {
      case full        // local network — all phases
      case remote      // remote subnet — TCP + ICMP + DNS only
  }
  ```
- Extend `ScanContext` with `networkProfile` and `scanStrategy`
- Add `ScanPipeline.forStrategy(_ strategy: ScanStrategy)`:
  - `.full` → existing `ScanPipeline.standard()`
  - `.remote` → pipeline with only TCPProbeScanPhase, ICMPLatencyPhase, ReverseDNSScanPhase
- Modify `ScanEngine.scan()` to accept strategy (backward compatible — defaults to `.full`)
- **Subnet generation for remote networks**: `IPv4Helpers.hostsInSubnet(cidr:)` generates IP list from CIDR
- **Tests:** ScanPipeline strategy tests, IPv4Helpers CIDR parsing tests

### Phase 3: iOS UI — Network Switcher

**NM2-d8c.3 — Network picker UI (iOS)**
- **Dashboard:** Add network name/icon above the gateway card showing active network
- **Network Map:** Add segmented control or dropdown at top for switching between profiles
- **Add Network sheet:**
  - Tab 1: "From Discovered Devices" — list devices that look like routers (gateway IP, open ports 80/443, UPnP)
  - Tab 2: "Manual" — text fields for gateway IP, subnet CIDR, name
  - Validation: check gateway is reachable (quick ICMP ping) before adding
- **Network badge:** Small indicator on device list showing which network each device belongs to
- Wire `NetworkProfileManager.switchProfile()` → triggers `DeviceDiscoveryService.startScan()` with new context
- **Tests:** UI tests for network picker, add network flow

### Phase 4: macOS UI — Network Switcher

**NM2-d8c.4 — Network picker UI (macOS)**
- **Sidebar:** Add "Networks" section above device list showing known networks
- **Network detail view:** clicking a network shows its devices
- **Add Network:** toolbar button or context menu, same options as iOS
- Wire to `DeviceDiscoveryCoordinator` — needs refactor to accept network profile
- **Tests:** UI tests for network switching

### Phase 5: Integration & Polish

**NM2-d8c.5 — Cross-platform integration and testing**
- **Companion Protocol enhancement:** When iOS connects to macOS companion, auto-add the macOS network as a profile (and vice versa)
- **Network health indicator:** Show per-network status (last scan time, device count, gateway reachability)
- **Data separation:** Ensure discovered devices are tagged with their network profile ID — don't mix devices from different networks
- **Persistence:** Device cache per network (not global)
- **Edge cases:**
  - Network goes offline → show stale data with "last seen" timestamp
  - Same device on multiple networks (e.g., router with two interfaces)
  - VPN connected → detect VPN subnet as additional network
- **Full integration tests:** Scan local → switch to manual remote → verify different device lists

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| ARP doesn't work on remote subnets | Use TCP+ICMP only strategy; clearly communicate "limited scan" in UI |
| Users add unreachable subnets | Validate reachability before adding; show error state with retry |
| Too many networks clutters UI | Cap at 5-10 profiles; archive inactive ones |
| Scanning multiple networks simultaneously | Serial by default; parallel as opt-in power feature later |
| Performance with large subnets (/16) | Warn on subnets > /24; default to /24 even if CIDR is larger |

---

## Estimated Effort

| Phase | Effort | Can Parallelize? |
|-------|--------|-----------------|
| Phase 1: Core Model & Manager | 2-3 hours | Standalone |
| Phase 2: Scan Strategy | 2-3 hours | After Phase 1 |
| Phase 3: iOS UI | 3-4 hours | After Phase 1 |
| Phase 4: macOS UI | 3-4 hours | After Phase 1, parallel with Phase 3 |
| Phase 5: Integration | 2-3 hours | After all phases |
| **Total** | **12-17 hours** | |

**Recommended execution:** Phase 1 first (solo agent), then Phase 2+3+4 in parallel (3 agents), Phase 5 last (solo agent with verification).

---

## Open Questions for Blake

1. **Should we support /16 or /8 subnets?** Could be thousands of hosts. Recommend limiting to /24 by default with a warning for larger.
2. **Auto-discovery of routers:** How aggressive? UPnP scan + checking common router ports (80, 443, 8080) + MAC vendor lookup?
3. **Companion Protocol integration:** Priority now or defer to a later update?
4. **Network naming:** Auto-detect from SSID (iOS) / interface name (macOS), or always ask the user?
5. **Simultaneous scanning:** Scan multiple networks at once, or switch-and-scan?
