<div align="center">

# NetMonitor

**Professional-grade network monitoring for macOS and iOS.**

A native Swift application with complete visibility into your network. Discover devices, diagnose connectivity, monitor uptime, and run professional diagnostics — all from a single cross-platform codebase.

[![macOS](https://img.shields.io/badge/macOS-15%2B-007AFF?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![iOS](https://img.shields.io/badge/iOS-18%2B-007AFF?style=flat-square&logo=apple)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-4A4A4A?style=flat-square)](LICENSE)

[Features](#features) • [Architecture](#architecture) • [Quick Start](#quick-start) • [Tools](#network-tools)

</div>

---

## Why NetMonitor?

Modern networks are complex. You need visibility into what's happening — who's connected, what's responding, and where problems are.

| Need | Solution |
|------|----------|
| **"What's on my network?"** | Multi-phase scanner (ARP + Bonjour + TCP + SSDP + ICMP) |
| **"Is my internet stable?"** | Continuous monitoring with latency graphs and uptime history |
| **"Why can't I reach X?"** | 14+ diagnostic tools — ping, traceroute, port scan, DNS, WHOIS, speed test |
| **"I need to prove coverage"** | WiFi heatmap with AR-assisted site survey |
| **"I manage multiple hosts"** | Target monitoring with custom intervals and alert thresholds |

---

## Features

### 📊 Dashboard & Device Discovery

| Feature | Description |
|---------|-------------|
| **Real-time overview** | Connection status, gateway info, public IP, ISP details, latency |
| **Network health score** | Composite metric from latency, packet loss, device responsiveness |
| **Device discovery** | Multi-phase scan (ARP + Bonjour + TCP + SSDP + ICMP) finds every device |
| **Device details** | MAC address, vendor lookup, open ports, hostname, Bonjour services |
| **VPN detection** | Identifies active VPN connections and tunnel interface details |
| **Change alerts** | Notifications when new devices appear or known devices disappear |

### 🛠️ Network Tools

| Tool | macOS | iOS | Description |
|------|:-----:|:---:|-------------|
| **Ping** | ✅ | ✅ | Continuous ICMP with live stats, jitter, packet loss graphing |
| **Traceroute** | ✅ | ✅ | Hop-by-hop path analysis with latency per hop |
| **GeoTrace** | ✅ | ✅ | Visual traceroute on MapKit world map |
| **DNS Lookup** | ✅ | ✅ | Query A, AAAA, MX, CNAME, TXT, NS, SOA, PTR records |
| **Port Scanner** | ✅ | ✅ | TCP connect scan with presets (Common, Web, Database, All) |
| **WHOIS** | ✅ | ✅ | Domain and IP registration lookups |
| **Speed Test** | ✅ | ✅ | Download/upload throughput with progress tracking |
| **Bonjour Browser** | ✅ | ✅ | Discover all mDNS services on local network |
| **Wake on LAN** | ✅ | ✅ | Send magic packets to wake sleeping devices |
| **SSL Certificate** | ✅ | ❌ | Inspect certificate chains, expiration dates, issuers |
| **Subnet Calculator** | ✅ | ❌ | CIDR notation, network/broadcast address, host range |
| **World Ping** | ✅ | ✅ | Ping global endpoints for latency visualization |
| **WiFi Heatmap** | ✅ | ✅ | Signal strength survey with thermal gradient overlay |
| **Web Browser** | ❌ | ✅ | In-app browser for testing connectivity |

### 🖥️ macOS Features

- **Sidebar navigation** — Dashboard, Devices, Networks, Targets, Tools
- **Target monitoring** — Add hosts with HTTP/ICMP/TCP checks and uptime history
- **Network detail** — Per-SSID statistics, device history, profile management
- **Timeline** — Event history log of network changes, scans, alerts
- **Menu bar app** — Quick-glance network status from macOS menu bar
- **Scheduled scans** — Automatic periodic device discovery
- **Shell-based diagnostics** — Maximum accuracy with system binaries

### 📱 iOS Features

- **Liquid Glass UI** — Custom design system with translucent cards
- **Network map** — Visual topology of discovered devices
- **Mac companion** — Connect to NetMonitor Pro for remote diagnostics
- **Home screen widgets** — Network status at a glance
- **AR WiFi signal** — Augmented reality overlay for signal strength
- **GeoFence monitoring** — Automatic scans on location changes

### 📡 WiFi Heatmap & Site Survey

Professional WiFi site survey tool:

| Phase | Description |
|-------|-------------|
| **Blueprint Import** | Import floor plan images, calibrate to real-world scale |
| **Walk Survey** | Click/tap measurement points during walkthrough |
| **Thermal Map** | IDW interpolation generates smooth heatmap overlay |
| **AR-Assisted** | LiDAR scanning generates floor plans from geometry |
| **AR Continuous** | Real-time Metal rendering composites heatmap over camera feed |
| **Export** | Save `.netmonsurvey` bundles, export PDF reports (macOS) |

### 🔗 Mac–iOS Companion Protocol

Pair iOS with Mac over local network:

- **Bonjour discovery** (`_netmon._tcp` on port 8849)
- **JSON protocol** — Newline-delimited JSON over `NWConnection`
- **Remote execution** — iOS leverages Mac's shell-based tools
- **Live streaming** — Real-time results pushed to iOS

---

## Requirements

| Platform | Minimum |
|----------|---------|
| macOS | 15.0 (Sequoia) |
| iOS | 18.0 |
| Xcode | 16.0 |
| Swift | 6.0 |

---

## Quick Start

### From Source

```bash
# Clone
git clone https://github.com/blakecrane/NetMonitor-2.0.git
cd NetMonitor-2.0

# Install XcodeGen
brew install xcodegen

# Generate project
xcodegen generate

# Open
open NetMonitor-2.0.xcodeproj
```

Select **NetMonitor-macOS** or **NetMonitor-iOS** scheme and build (⌘B).

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

### App Store

| Platform | Link |
|----------|------|
| **macOS** | [NetMonitor Pro — $9.99](https://apps.apple.com/app/netmonitor-pro/id6759060882) |
| **iOS** | [NetMonitor Mobile — $4.99](https://apps.apple.com/app/netmonitor-ios/id6759060947) |

---

## Architecture

Monorepo with two local Swift packages and two platform targets:

```
NetMonitor-2.0/
├── Packages/
│   ├── NetMonitorCore/          # Shared models, protocols, services (~5,600 LOC)
│   │   └── Sources/NetMonitorCore/
│   │       ├── Models/          # CompanionMessage, NetworkModels, etc.
│   │       └── Services/        # 20+ service protocols + implementations
│   └── NetworkScanKit/          # Device discovery engine (~2,200 LOC)
│       └── Sources/NetworkScanKit/
│           ├── ScanEngine, ScanPipeline, ScanContext
│           ├── Phases/          # ARP, Bonjour, TCP, SSDP, ICMP, DNS
│           └── ConnectionBudget, ThermalThrottleMonitor
├── NetMonitor-macOS/            # macOS app
│   ├── Views/                   # Dashboard, Devices, Targets, Tools, Settings
│   ├── MenuBar/                 # Menu bar popover and commands
│   └── Platform/               # Shell services, companion host, ARP scanner
├── NetMonitor-iOS/              # iOS app
│   ├── Views/                   # Dashboard, NetworkMap, DeviceDetail, Tools
│   ├── ViewModels/              # @Observable ViewModels (25 files)
│   ├── Platform/               # Theme, GlassCard, MacConnectionService
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
          │   NetworkScanKit   │
          │  scan engine · ARP │
          │  Bonjour · TCP/SSDP│
          └─────────────────────┘
```

### Key Services

| Service | Protocol | Description |
|---------|----------|-------------|
| DeviceDiscovery | `DeviceDiscoveryServiceProtocol` | Multi-phase LAN scanning via NetworkScanKit |
| Ping | `PingServiceProtocol` | Continuous ICMP with `AsyncStream<PingResult>` |
| Traceroute | `TracerouteServiceProtocol` | Hop-by-hop tracing with `AsyncStream<TracerouteHop>` |
| PortScanner | `PortScannerServiceProtocol` | TCP connect scanner with `AsyncStream<PortScanResult>` |
| DNS Lookup | `DNSLookupServiceProtocol` | Multi-record-type DNS resolution |
| WHOIS | `WHOISServiceProtocol` | Domain/IP WHOIS queries |
| SpeedTest | `SpeedTestServiceProtocol` | Download/upload throughput measurement |
| Bonjour | `BonjourDiscoveryServiceProtocol` | mDNS service browser |
| WakeOnLAN | `WakeOnLANServiceProtocol` | Magic packet sender |
| SSL Certificate | `SSLCertificateServiceProtocol` | TLS certificate chain inspector |
| NetworkHealthScore | `NetworkHealthScoreServiceProtocol` | Composite network quality metric |
| VPN Detection | `VPNDetectionServiceProtocol` | Active VPN tunnel identification |
| WorldPing | `WorldPingServiceProtocol` | Global endpoint latency measurement |
| WiFi Heatmap | `WiFiHeatmapServiceProtocol` | Signal strength survey and thermal mapping |

### Key Patterns

| Pattern | Description |
|---------|-------------|
| **Protocol-backed services** | Every service conforms to a protocol for DI and testability |
| **Observable ViewModels** | `@MainActor @Observable final class` |
| **AsyncStream** | Long-running operations yield incremental results |
| **Actor-based concurrency** | Swift 6 strict concurrency with `Sendable` protocols |
| **Multi-phase scan pipeline** | ARP + Bonjour → TCP + SSDP → ICMP → DNS with connection budgeting |

---

## Contributing

1. **Fork** the repository
2. **Create a branch:** `git checkout -b feature/my-feature`
3. **Install XcodeGen** — regenerate after any `project.yml` changes
4. **Ensure strict concurrency** — project uses `SWIFT_STRICT_CONCURRENCY: complete`
5. **Run tests:** `xcodebuild test -scheme NetMonitor-macOS`
6. **Open a pull request** against `main`

---

## License

MIT License. See [LICENSE](LICENSE) for details.

Copyright © 2026 Blake Crane

---

<div align="center">

**[macOS App Store](https://apps.apple.com/app/netmonitor-pro/id6759060882)** • 
**[iOS App Store](https://apps.apple.com/app/netmonitor-ios/id6759060947)** • 
**[Report a Bug](https://github.com/blakecrane/NetMonitor-2.0/issues/new?labels=bug)**

</div>