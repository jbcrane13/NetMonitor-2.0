<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitor-macOS/Platform

## Purpose
macOS-specific service implementations. Implements protocols from `NetMonitorCore/Services/ServiceProtocols.swift` using macOS-native approaches: shell execution, raw sockets, SwiftData integration, and Bonjour advertisement.

## Key Files

| File | Description |
|------|-------------|
| `ShellCommandRunner.swift` | Executes shell commands via `Foundation.Process` |
| `ShellPingService.swift` | Bare actor shelling to `/sbin/ping` for latency measurement (does not conform to `PingServiceProtocol`) |
| `ICMPMonitorService.swift` | Continuous ICMP monitoring using `ICMPSocket` (raw socket) |
| `HTTPMonitorService.swift` | HTTP/HTTPS target monitoring via `URLSession` |
| `TCPMonitorService.swift` | TCP connection monitoring via `NWConnection` |
| `CompanionService.swift` | Bonjour advertisement (`_netmon._tcp`, port 8849) + `NWListener` for iOS connections |
| `CompanionMessageHandler.swift` | Processes `CompanionMessage` commands from iOS clients |
| `DeviceDiscoveryCoordinator.swift` | Runs the NetworkScanKit `ScanEngine` pipeline and merges results into SwiftData `LocalDevice` rows (online, cached, offline) |
| `Phases/` | macOS enrichment phases appended to `ScanPipeline.standard`: shell name resolution, vendor lookup, quick port scan, shell ping |
| `MacNetworkMonitor.swift` | Implements `NetworkMonitorServiceProtocol` for macOS using `NWPathMonitor` |
| `NetworkInfoService.swift` | Reads network interface configuration (IP, subnet, gateway) |
| `ISPLookupService.swift` | Fetches ISP/geolocation info for public IP |
| `StatisticsService.swift` | Aggregates monitoring statistics across targets and sessions |
| `MonitoringSession.swift` | Coordinates a monitoring session: starts/stops per-target monitors |
| `DefaultTargetsProvider.swift` | Provides default monitoring targets (gateway, DNS, well-known hosts) |
| `ShellDeviceNameResolver.swift` | Caching reverse-DNS resolver for discovered devices |
| `Logging.swift` | `OSLog` category setup for the macOS target |

## For AI Agents

### Device discovery
There is no `ARPScannerService`; ARP discovery lives in NetworkScanKit (`ARPScanPhase`, `ARPCacheScanner`): UDP probes, a `sysctl` read of the ARP table (empty for the sandboxed app on macOS 27, #401), settle polling, and an ARP re-check after ICMP. See `Packages/NetworkScanKit/Sources/NetworkScanKit/Phases/AGENTS.md`.

A completed scan's rows are kept current by Core `ScanReconciler`, the iPhone's too (#596), through `DeviceDiscoveryCoordinator.reconcileScan`, in its own `ModelContext` on the shared container:
- Which row comes from `PresenceMatch`. Without a real MAC (every device on macOS 27), an address identifies a row only with agreeing names, or, when a name is unknown, if the row was seen there within grace or by the network's previous scan when that scan was at most 2 h earlier (`PresenceMatch.previousScanReach`). Otherwise the device gets a new row.
- An answering device's row is `.online` with `lastSeen` = the scan's time. A cached sighting (ARP cache only) is a miss: its row becomes `.cached` and keeps `lastSeen`. A cached sighting never makes a row.
- A row goes `.offline` only under `DeviceGracePolicy` (3 missed scans and 15 minutes). A scan in which nothing answered changes nothing, and neither the rows nor the Timeline move.
- Each network's reconciled scans are in `ScanHistory` (UserDefaults; a UI-test suite under `--uitesting`). Clearing the data clears it.

`mergeSparseSnapshot`, at the enrichment transition, touches only the latency of rows with the device's own real MAC (status is left to the final pass, so a cancelled scan never leaves an old row Online), and inserts only public MACs that no row on the network, or saved without one, already has. The coordinator's clock is read once per scan for the sparse merge, the reconcile and the change tracker. Online counts, the menu bar and the companion's `isOnline` count only `.online`.

### Shell Command Pattern
```swift
// ShellCommandRunner is an actor
let runner = ShellCommandRunner()
let output = try await runner.run("/sbin/ping", arguments: ["-c", "1", host])
```

### Companion Protocol
Wire format is newline-delimited JSON. Message types and payloads are defined in `NetMonitorCore/CompanionMessage.swift`. See `docs/Companion-Protocol-API.md` for the full protocol spec.

### Adding a New Service
1. Define the protocol in `NetMonitorCore/Services/ServiceProtocols.swift`
2. Implement here conforming to the protocol
3. Register in `NetMonitorApp.swift` as an environment object or inject into the coordinator

### Dependencies

#### Internal
- `NetMonitorCore` — protocols, `CompanionMessage`, models
- `NetworkScanKit` — `DiscoveredDevice`, scan engine

#### External
- `Network` — `NWConnection`, `NWListener`, `NWPathMonitor`
- `dnssd` — Bonjour via `NWListener` with Bonjour parameters

<!-- MANUAL: -->
