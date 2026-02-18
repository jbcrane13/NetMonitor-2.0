<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitorCore/Services

## Purpose
Service protocols and platform-agnostic service implementations. `ServiceProtocols.swift` is the canonical contract that both app targets must implement. Platform-specific implementations live in the app targets' `Platform/` directories.

## Key Files

| File | Description |
|------|-------------|
| `ServiceProtocols.swift` | All 20+ service protocol definitions — the shared contract for both platforms |
| `DeviceDiscoveryService.swift` | `@MainActor @Observable` discovery coordinator wrapping `NetworkScanKit` |
| `PingService.swift` | Platform-agnostic ping via Network framework (iOS primary path) |
| `PortScannerService.swift` | Concurrent TCP port scanner returning `AsyncStream<PortScanResult>` |
| `DNSLookupService.swift` | DNS record queries supporting A, AAAA, MX, TXT, CNAME, NS, SOA, PTR |
| `WHOISService.swift` | WHOIS TCP queries to whois servers |
| `BonjourDiscoveryService.swift` | mDNS service browser via `NetServiceBrowser` |
| `TracerouteService.swift` | ICMP traceroute via TTL-manipulation |
| `SpeedTestService.swift` | Download/upload speed test with phase streaming |
| `WakeOnLANService.swift` | UDP magic packet sender |
| `NetworkMonitorService.swift` | Platform-agnostic network path monitoring via `NWPathMonitor` |
| `NotificationService.swift` | Local notification scheduling for monitoring alerts |
| `ICMPSocket.swift` | Raw ICMP socket wrapper (requires entitlement) |
| `MACVendorLookupService.swift` | IEEE OUI database lookup for MAC vendor identification |

## For AI Agents

### Service Protocol Pattern
```swift
// In ServiceProtocols.swift
public protocol FooServiceProtocol: AnyObject, Sendable {
    func run(input: String) async -> AsyncStream<FooResult>
    func stop() async
}
```

### Implementation Rules
- All protocols must be `Sendable` to cross actor boundaries
- Use `AsyncStream<T>` for streaming operations
- `@MainActor` isolation only on properties that directly update UI state
- Platform-specific implementations go in the app targets — not here

### Key Services by Platform

| Service | macOS Implementation | iOS Implementation |
|---------|---------------------|-------------------|
| Ping | `ShellPingService` (shells to `/sbin/ping`) | `PingService` (Network framework) |
| ARP/Discovery | `ARPScannerService` (shells to `arp`) | `NetworkScanKit` + companion |
| ICMP monitoring | `ICMPMonitorService` (raw socket) | Via companion to macOS |
| Network info | `NetworkInfoService` (system APIs) | `WiFiInfoService` + `GatewayService` |

<!-- MANUAL: -->
