# NetMonitor 2.0 — Feature Lists

*Generated: 2026-02-23*

---

## iOS Features

### Core Features
- **Network Dashboard** — Real-time network status, device count, gateway info, ISP details, public IP
- **Network Map** — Visual network topology with device tiles, status indicators, scan controls
- **Device Discovery** — Multi-phase scanning (ARP + Bonjour + TCP probe + SSDP + ICMP latency + DNS)
- **Device Detail** — Full device info: IP, MAC, vendor, hostname, open ports, Bonjour services

### Tools (9 tools)
| Tool | Description |
|------|-------------|
| **Ping** | ICMP-primary with TCP fallback, live stats, packet loss %, RTT graph |
| **Traceroute** | Visual hop-by-hop with GeoTrace map view (MapKit) |
| **DNS Lookup** | A, AAAA, MX, NS, TXT, CNAME records |
| **Port Scanner** | Preset + custom ports, service detection |
| **WHOIS** | Domain registration lookup |
| **Bonjour Discovery** | mDNS service browser with tiered browsing |
| **Speed Test** | Download/upload throughput measurement |
| **Wake on LAN** | Magic packet sender |
| **Web Browser** | Router admin bookmarks, target-aware URL injection |

### 2.0 New Features (Completed 2026-02-23)
| Feature | Description |
|---------|-------------|
| **GeoTrace** | Visual traceroute with hop geolocation on MapKit |
| **Subnet Calculator** | CIDR calculator, subnet ranges, usable hosts |
| **Health Score** | Network health assessment (latency, packet loss, DNS response) |
| **VPN Detection** | Detect active VPN connection status |
| **Scheduled Scans** | Background scan scheduling with change detection alerts |
| **GeoFence** | Location-based network context triggers |
| **Timeline/Event History** | Historical scan results and network events |
| **SSL Monitor** | Certificate expiry monitoring for HTTPS endpoints |
| **WiFi Heatmapping** | Signal strength mapping across locations |

### Infrastructure
- **Multi-Network Support** — Network profiles with auto-discovery + manual add
- **Mac Companion** — Connect to macOS app via Bonjour (`_netmon._tcp`) for extended capabilities
- **Background Tasks** — `BGTaskScheduler` for periodic scans
- **Widget** — Home screen + lock screen widgets
- **Liquid Glass UI** — Modern iOS 26 visual design
- **Target Manager** — Quick-target selection across tools

---

## macOS Features

### Core Features
- **Dashboard** — Real-time network overview, device count, gateway/router info
- **Devices View** — Scanned device list with filtering, sorting, detail sheets
- **Network Detail** — Per-network statistics, device history, session records
- **Targets View** — Monitored host list with uptime tracking
- **Sidebar Navigation** — Section-based navigation (Dashboard, Devices, Networks, Targets, Tools)

### Tools (8 tools)
| Tool | Description |
|------|-------------|
| **Ping** | Shell-based ping with live stats, ICMP-accurate RTT |
| **Traceroute** | Hop-by-hop with resolved hostnames |
| **DNS Lookup** | Multi-record DNS queries |
| **Port Scanner** | TCP connect probes with service detection |
| **WHOIS** | Domain registration lookup |
| **Bonjour Browser** | LAN service discovery |
| **Speed Test** | Parallel download/upload measurement |
| **Wake on LAN** | Magic packet sender |

### 2.0 New Features | Feature | Description |
|---------|-------------|
| **GeoTrace** | Visual traceroute with MapKit hop visualization |
| **Subnet Calculator** | CIDR math, subnet ranges |
| **Health Score** | Network quality assessment |
| **VPN Detection** | Active VPN status |
| **Scheduled Scans** | Automated scanning with change alerts |
| **GeoFence** | Location-triggered network context |
| **Timeline/Event History** | Historical records |
| **SSL Monitor** | HTTPS certificate monitoring |
| **WiFi Heatmapping** | Signal mapping |
| **WiFi Heatmapping** | Signal mapping |

### macOS-Specific Features
- **Menu Bar App** — Quick network status from menu bar
- **SwiftData Persistence** — `NetworkTarget`, `LocalDevice`, `SessionRecord` models
- **Companion Service** — Advertises `_netmon._tcp` on port 8849 for iOS connection
- **Shell Integration** — Uses system `ping`, `arp`, `traceroute` commands
- **Settings Panes** — Native macOS Settings window

---

## Shared Infrastructure (Both Platforms)

- **NetMonitorCore** — Shared models, service protocols, utilities
- **NetworkScanKit** — Multi-phase scan engine with `ConnectionBudget` throttling
- **Swift 6 Strict Concurrency** — Full `Sendable` compliance
- **XcodeGen** — `project.yml`-driven project generation
