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

`DeviceDiscoveryCoordinator.mergeDiscoveredDevices` maps each device's `isCached` to `DeviceStatus.cached` (no answer this scan; `lastSeen` is left alone) or `.online` (`lastSeen` = now). `markOfflineDevices` sets `.offline` for rows not in the scan result. Online counts, the menu bar and the companion's `isOnline` count only `.online`.

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
