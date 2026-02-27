<p align="center">
  <h1 align="center">NetMonitor</h1>
  <p align="center">Professional-grade network monitoring and diagnostics for macOS and iOS</p>
</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/macOS-15.0%2B-blue?logo=apple&logoColor=white" alt="macOS 15.0+"></a>
  <a href="#"><img src="https://img.shields.io/badge/iOS-18.0%2B-blue?logo=apple&logoColor=white" alt="iOS 18.0+"></a>
  <a href="#"><img src="https://img.shields.io/badge/Swift-6.0-orange?logo=swift&logoColor=white" alt="Swift 6.0"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License"></a>
</p>

<!-- Screenshots (uncomment when assets are available)
<p align="center">
  <img src="docs/screenshots/macos-dashboard.png" width="720" alt="NetMonitor macOS Dashboard">
</p>
<p align="center">
  <img src="docs/screenshots/ios-dashboard.png" width="280" alt="NetMonitor iOS Dashboard">
  <img src="docs/screenshots/ios-tools.png" width="280" alt="NetMonitor iOS Tools">
  <img src="docs/screenshots/ios-network-map.png" width="280" alt="NetMonitor iOS Network Map">
</p>
-->

## What is NetMonitor?

NetMonitor is a native Swift application that gives you complete visibility into your network. Discover every device, diagnose connectivity issues, monitor uptime, and run professional diagnostics — all from a single app on your Mac or iPhone.

Version 2.0 is a ground-up rewrite with a shared core architecture, 14+ diagnostic tools, a companion protocol that bridges macOS and iOS, and full Swift 6 strict concurrency.

## Features

### Dashboard & Device Discovery

- **Real-time network overview** — connection status, gateway info, public IP, ISP details, and latency analysis at a glance
- **Network health score** — composite health metric derived from latency, packet loss, and device responsiveness
- **Device discovery** — multi-phase scan engine (ARP + Bonjour + TCP probe + SSDP + ICMP) identifies every device on your LAN
- **Device detail sheets** — MAC address, vendor lookup, open ports, hostname, Bonjour services, and latency history per device
- **VPN detection** — identifies active VPN connections and displays tunnel interface details
- **Scan change alerts** — notifies you when new devices appear or known devices disappear

### Network Tools

| Tool | Description |
|---|---|
| **Ping** | Continuous ICMP ping with live statistics, jitter, and packet loss graphing |
| **Traceroute** | Hop-by-hop path analysis with latency per hop |
| **GeoTrace** | Visual traceroute plotted on a MapKit world map |
| **DNS Lookup** | Query A, AAAA, MX, CNAME, TXT, NS, SOA, and PTR records |
| **Port Scanner** | TCP connect scan with preset profiles (Common, Web, Database, All) |
| **WHOIS** | Domain and IP registration lookups |
| **Speed Test** | Download and upload throughput measurement with progress tracking |
| **Bonjour Browser** | Discover and inspect all Bonjour/mDNS services on the local network |
| **Wake on LAN** | Send magic packets to wake sleeping devices by MAC address |
| **SSL Certificate Monitor** | Inspect certificate chains, expiration dates, and issuer details |
| **Subnet Calculator** | CIDR notation, network/broadcast address, and host range computation |
| **World Ping** | Ping global endpoints to visualize latency from your location |
| **WiFi Heatmap** | Walk-survey tool that maps signal strength across a floor plan with thermal gradient visualization |
| **Web Browser** | *(iOS only)* Lightweight in-app browser for testing connectivity to specific URLs |

### macOS

- **Sidebar navigation** with Dashboard, Devices, Networks, Targets, and Tools sections
- **Targets view** — add monitored hosts with HTTP/ICMP/TCP checks and uptime history
- **Network detail** — per-SSID statistics, device history, and profile management
- **Timeline** — event history log of network changes, scans, and alerts
- **Menu bar app** — quick-glance network status from the macOS menu bar
- **Scheduled scans** — automatic periodic device discovery
- **SwiftData persistence** — local storage for devices, targets, sessions, and network profiles
- **Shell-based diagnostics** — leverages system binaries (`ping`, `arp`, `traceroute`) for maximum accuracy

### iOS

- **Liquid Glass UI** — custom design system with translucent cards, glass buttons, and themed components
- **Network map** — visual topology of discovered devices
- **Mac companion** — connect to a paired Mac running NetMonitor to execute privileged scans remotely
- **Home screen widgets** — network status widget showing connection type, SSID, latency, and device count
- **GeoFence monitoring** — trigger network scans automatically when entering or leaving configured locations
- **Scheduled background scans** — configurable scan intervals that run via `BGTaskScheduler`
- **AR WiFi signal view** — augmented reality overlay showing real-time signal strength

### Mac–iOS Companion Protocol

NetMonitor on iOS can pair with a Mac running NetMonitor over the local network. The companion protocol uses Bonjour discovery (`_netmon._tcp` on port 8849) and exchanges newline-delimited JSON messages over `NWConnection`. This lets the iOS app leverage the Mac's shell-based tools (raw ICMP, ARP scanning) that aren't available on iOS.

## Requirements

| | Minimum |
|---|---|
| **macOS** | 15.0 (Sequoia) |
| **iOS** | 18.0 |
| **Xcode** | 16.0 |
| **Swift** | 6.0 |

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/blakecrane/NetMonitor-2.0.git
cd NetMonitor-2.0

# Install XcodeGen if needed
brew install xcodegen

# Generate the Xcode project
xcodegen generate

# Open in Xcode
open NetMonitor-2.0.xcodeproj
```

Select the **NetMonitor-macOS** or **NetMonitor-iOS** scheme and build (⌘B).

### Command Line

```bash
# Build macOS
xcodebuild -scheme NetMonitor-macOS -configuration Debug build

# Build iOS (simulator)
xcodebuild -scheme NetMonitor-iOS -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run tests
xcodebuild test -scheme NetMonitor-macOS
xcodebuild test -scheme NetMonitor-iOS
```

<!-- ### App Store
Coming soon.
-->

## Architecture

NetMonitor is a monorepo with two local Swift packages and two platform targets:

```
NetMonitor-2.0/
├── Packages/
│   ├── NetMonitorCore/          # Shared models, protocols, services  (~5,600 LOC)
│   │   └── Sources/
│   │       └── NetMonitorCore/
│   │           ├── Models/      # CompanionMessage, Enums, NetworkModels, etc.
│   │           └── Services/    # 20+ service protocols + shared implementations
│   └── NetworkScanKit/          # Device discovery engine              (~2,200 LOC)
│       └── Sources/
│           └── NetworkScanKit/
│               ├── ScanEngine, ScanPipeline, ScanContext
│               ├── Phases/      # ARP, Bonjour, TCP, SSDP, ICMP, DNS phases
│               └── ConnectionBudget, ThermalThrottleMonitor
├── NetMonitor-macOS/
│   ├── Views/                   # Dashboard, Devices, Targets, Tools, Settings
│   ├── MenuBar/                 # Menu bar popover and commands
│   └── Platform/                # Shell services, companion host, ARP scanner
├── NetMonitor-iOS/
│   ├── Views/                   # Dashboard, NetworkMap, DeviceDetail, Tools, Settings
│   ├── ViewModels/              # @Observable ViewModels (25 files)
│   ├── Platform/                # Theme, GlassCard, MacConnectionService
│   └── Widget/                  # Home screen widget
├── Tests/                       # 111 test files
├── docs/                        # ADRs, protocol spec, PRDs
└── project.yml                  # XcodeGen manifest
```

### Dependency Chain

```
┌─────────────────┐     ┌─────────────────┐
│ NetMonitor-macOS │     │  NetMonitor-iOS  │
└────────┬────────┘     └────────┬────────┘
         │                       │
         └───────────┬───────────┘
                     ▼
          ┌─────────────────────┐
          │   NetMonitorCore    │
          │  models · protocols │
          │  shared services    │
          └──────────┬──────────┘
                     ▼
          ┌─────────────────────┐
          │   NetworkScanKit    │
          │  scan engine · ARP  │
          │  Bonjour · TCP/SSDP │
          └─────────────────────┘
```

### Key Services

| Service | Protocol | Description |
|---|---|---|
| DeviceDiscovery | `DeviceDiscoveryServiceProtocol` | Coordinates multi-phase LAN scanning via NetworkScanKit |
| Ping | `PingServiceProtocol` | Continuous ICMP ping with `AsyncStream<PingResult>` |
| Traceroute | `TracerouteServiceProtocol` | Hop-by-hop path tracing with `AsyncStream<TracerouteHop>` |
| PortScanner | `PortScannerServiceProtocol` | TCP connect scanner with `AsyncStream<PortScanResult>` |
| DNS Lookup | `DNSLookupServiceProtocol` | Multi-record-type DNS resolution |
| WHOIS | `WHOISServiceProtocol` | Domain/IP WHOIS queries |
| SpeedTest | `SpeedTestServiceProtocol` | Download/upload throughput measurement |
| Bonjour | `BonjourDiscoveryServiceProtocol` | mDNS service browser |
| WakeOnLAN | `WakeOnLANServiceProtocol` | Magic packet sender |
| SSL Certificate | `SSLCertificateServiceProtocol` | TLS certificate chain inspector |
| NetworkMonitor | `NetworkMonitorServiceProtocol` | Connectivity and interface change tracking |
| NetworkHealthScore | `NetworkHealthScoreServiceProtocol` | Composite network quality metric |
| VPN Detection | `VPNDetectionServiceProtocol` | Active VPN tunnel identification |
| GeoLocation | `GeoLocationServiceProtocol` | IP-to-location mapping for GeoTrace |
| WorldPing | `WorldPingServiceProtocol` | Global endpoint latency measurement |
| MAC Vendor Lookup | `MACVendorLookupServiceProtocol` | OUI database lookup for device identification |
| Notification | `NotificationServiceProtocol` | System notification delivery |
| ScanScheduler | `ScanSchedulerServiceProtocol` | Periodic automatic scanning |
| WiFi Heatmap | `WiFiHeatmapServiceProtocol` | Signal strength survey and thermal mapping |

### Key Patterns

- **Protocol-backed services** — every service conforms to a protocol defined in `ServiceProtocols.swift` for dependency injection and testability
- **Observable ViewModels** (iOS) — `@MainActor @Observable final class` ViewModels keep views free of business logic
- **AsyncStream** — long-running operations (ping, port scan, traceroute) yield incremental results via `AsyncStream<T>`
- **Actor-based concurrency** — Swift 6 strict concurrency with `Sendable` protocols, actors, and `@MainActor` isolation
- **Multi-phase scan pipeline** — NetworkScanKit runs ARP + Bonjour → TCP + SSDP → ICMP → DNS phases with connection budgeting and thermal throttling

## Project Structure

| Directory | Contents |
|---|---|
| `Packages/NetMonitorCore/` | Shared models, enums, service protocols, and platform-agnostic service implementations |
| `Packages/NetworkScanKit/` | `ScanEngine`, `ScanPipeline`, phase runners, `ConnectionBudget`, `ThermalThrottleMonitor` |
| `NetMonitor-macOS/Views/` | Dashboard, Devices, Targets, Networks, Tools (14 tools), Settings (7 panes), Timeline |
| `NetMonitor-macOS/MenuBar/` | `MenuBarController`, `MenuBarPopoverView`, `MenuBarCommands` |
| `NetMonitor-macOS/Platform/` | Shell services, companion host, ARP scanner, ISP lookup, monitoring sessions |
| `NetMonitor-iOS/Views/` | Dashboard, NetworkMap, DeviceDetail, Tools (15 tools), Settings, Timeline, Components |
| `NetMonitor-iOS/ViewModels/` | 25 `@Observable` ViewModels |
| `NetMonitor-iOS/Platform/` | Theme system, GlassCard, MacConnectionService |
| `NetMonitor-iOS/Widget/` | Home screen widget with network status |
| `Tests/` | 111 test files covering core services, models, and view models |
| `docs/` | Architecture docs, ADRs, companion protocol spec, PRDs |

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) and regenerate after any `project.yml` changes
4. Ensure strict concurrency compliance — the project uses `SWIFT_STRICT_CONCURRENCY: complete`
5. Run the test suite before submitting (`xcodebuild test -scheme NetMonitor-macOS`)
6. Open a pull request

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

Copyright (c) 2026 Blake Crane
