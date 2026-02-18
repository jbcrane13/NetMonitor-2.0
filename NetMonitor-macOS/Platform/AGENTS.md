<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitor-macOS/Platform

## Purpose
macOS-specific service implementations. Implements protocols from `NetMonitorCore/Services/ServiceProtocols.swift` using macOS-native approaches: shell execution, raw sockets, SwiftData integration, and Bonjour advertisement.

## Key Files

| File | Description |
|------|-------------|
| `ShellCommandRunner.swift` | Executes shell commands via `Foundation.Process`; used by ping and ARP services |
| `ShellPingService.swift` | Implements `PingServiceProtocol` by shelling to `/sbin/ping` |
| `ARPScannerService.swift` | Implements device discovery by parsing `arp -a` output |
| `ICMPMonitorService.swift` | Continuous ICMP monitoring using `ICMPSocket` (raw socket) |
| `HTTPMonitorService.swift` | HTTP/HTTPS target monitoring via `URLSession` |
| `TCPMonitorService.swift` | TCP connection monitoring via `NWConnection` |
| `CompanionService.swift` | Bonjour advertisement (`_netmon._tcp`, port 8849) + `NWListener` for iOS connections |
| `CompanionMessageHandler.swift` | Processes `CompanionMessage` commands from iOS clients |
| `DeviceDiscoveryCoordinator.swift` | Bridges `DeviceDiscoveryService` with SwiftData (`LocalDevice` upsert) |
| `MacNetworkMonitor.swift` | Implements `NetworkMonitorServiceProtocol` for macOS using `NWPathMonitor` |
| `NetworkInfoService.swift` | Reads network interface configuration (IP, subnet, gateway) |
| `ISPLookupService.swift` | Fetches ISP/geolocation info for public IP |
| `StatisticsService.swift` | Aggregates monitoring statistics across targets and sessions |
| `MonitoringSession.swift` | Coordinates a monitoring session: starts/stops per-target monitors |
| `DefaultTargetsProvider.swift` | Provides default monitoring targets (gateway, DNS, well-known hosts) |
| `DeviceNameResolver.swift` | Caching reverse-DNS resolver for discovered devices |
| `Logging.swift` | `OSLog` category setup for the macOS target |

## For AI Agents

### Shell Command Pattern
```swift
// ShellCommandRunner is an actor
let runner = ShellCommandRunner()
let output = try await runner.run("/usr/sbin/arp", arguments: ["-a"])
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
