# NetMonitor for macOS - Product Requirements Document

## 1. Project Overview

### 1.1 Product Name
NetMonitorfor macOS

### 1.2 Description
A professional network monitoring application for macOS that provides real-time network diagnostics, target monitoring, local device discovery, and network utilities. The app serves as the primary monitoring hub that collects and displays comprehensive network data, and communicates with an iOS companion app.

### 1.3 Target Platform
- macOS 14.0 (Sonoma) and later
- Native SwiftUI application
- Universal binary (Apple Silicon + Intel)

### 1.4 Target Users
- Network administrators
- IT professionals
- Power users requiring network diagnostics
- Software developers debugging network issues

---

## 2. Technical Requirements

### 2.1 Frameworks & Technologies
- **UI**: SwiftUI with AppKit integration where needed
- **Networking**: Network.framework, NWPathMonitor
- **Local Discovery**: MultipeerConnectivity, Bonjour/mDNS
- **Data Persistence**: SwiftData or Core Data
- **Companion Communication**: Local network (Bonjour) + CloudKit for remote sync
- **Charts**: Swift Charts for visualizations
- **Concurrency**: Swift async/await, Actors

### 2.2 Architecture
- MVVM architecture pattern
- Protocol-oriented design for network services
- Dependency injection for testability
- Combine publishers for reactive data flow

### 2.3 Permissions Required
- Local Network access
- Location (for WiFi SSID on macOS)
- Outgoing network connections

---

## 3. Feature Specifications

### 3.1 Dashboard (Home Screen)

#### 3.1.1 Session Information
- Display monitoring session start date/time
- Running duration timer (HH:MM:SS format, updates every second)
- Start/Stop/Pause monitoring controls

#### 3.1.2 Connection Details Card
- Connection type (WiFi/Ethernet/Cellular)
- Network SSID (for WiFi)
- Signal strength with visual indicator (dBm value + bar graph)
- Access Point identifier
- Channel and frequency band (2.4GHz/5GHz/6GHz)
- Link speed

#### 3.1.3 Gateway Information Card
- Gateway IP address
- Gateway MAC address
- Vendor identification (MAC address lookup)
- Gateway latency (ping response time)

#### 3.1.4 ISP Information Card
- Public IP address (fetched from external service)
- ISP name
- ASN (Autonomous System Number)
- Geolocation (City, Country)
- Last updated timestamp
- Refresh button

#### 3.1.5 Quick Stats Bar
- Total devices on network
- Online/offline targets count
- Average latency
- Packet loss percentage

### 3.2 Target Monitoring

#### 3.2.1 Target Management
- Add/Edit/Remove monitoring targets
- Target properties:
  - Name (user-defined label)
  - Host (IP address or hostname)
  - Protocol (ICMP, HTTP, HTTPS, TCP)
  - Port (for TCP/HTTP/HTTPS)
  - Check interval (seconds)
  - Timeout threshold
  - Enabled/Disabled toggle

#### 3.2.2 Default Targets (Pre-configured)
- Gateway (auto-detected)
- Cloudflare DNS (1.1.1.1)
- Google DNS (8.8.8.8)
- Quad9 DNS (9.9.9.9)
- Major services: Google, Apple, Microsoft, Amazon, Netflix, Facebook

#### 3.2.3 Target Statistics Table
Display columns:
- Target name
- Protocol
- Current latency
- Latency stats (2min / 10min / all-time): min/avg/max
- Jitter stats (2min / 10min / all-time)
- Packet loss percentage (2min / 10min / all-time)
- Packets sent/received/lost
- Online/Offline status with indicator

#### 3.2.4 Target Detail View
- Historical latency graph (line chart)
- Historical packet loss graph
- Response time distribution histogram
- Uptime percentage
- Last 24-hour availability timeline
- Export statistics (CSV/JSON)

### 3.3 Local Device Discovery

#### 3.3.1 Network Scanner
- ARP scan for local network devices
- Bonjour/mDNS service discovery
- NetBIOS name resolution
- Configurable scan intervals
- Manual scan trigger button

#### 3.3.2 Device Information
- IP address
- MAC address
- Hostname (if discoverable)
- Vendor (MAC lookup)
- Device type (auto-detected or user-assigned)
- First seen timestamp
- Last seen timestamp
- Online/Offline status
- Custom name (user-assigned)
- Notes field

#### 3.3.3 Device Types
Support icons/categories for:
- Computer (Mac, Windows, Linux)
- Mobile (iPhone, iPad, Android)
- TV/Streaming devices
- Gaming consoles
- Smart speakers
- IoT devices
- Network equipment (routers, switches, APs)
- Printers
- Unknown/Other

#### 3.3.4 Network Map Visualization
- Radial topology view with gateway at center
- Device nodes positioned around gateway
- Connection lines showing relationships
- Color-coded status (green=active, gray=idle, red=offline)
- Click device to view details
- Drag to reposition nodes (optional)
- Zoom and pan controls

#### 3.3.5 Device Actions
- Ping device
- Port scan device
- Wake on LAN
- Copy IP/MAC to clipboard
- Add to monitoring targets
- Edit device details
- Delete/Hide device

### 3.4 Network Tools

#### 3.4.1 Ping Tool
- Target input (hostname or IP)
- Packet count selector
- Packet size option
- Interval setting
- Real-time results display
- Statistics summary (min/avg/max/stddev)
- Stop button for continuous ping

#### 3.4.2 Traceroute Tool
- Target input
- Max hops setting
- Protocol selection (ICMP/UDP)
- Real-time hop-by-hop display
- Latency per hop
- Visual path diagram
- Reverse DNS lookup option

#### 3.4.3 Port Scanner
- Target input
- Port range (start-end) or common ports preset
- Scan type (TCP connect, SYN)
- Concurrent connections limit
- Results list with port, service name, status
- Export results

#### 3.4.4 DNS Lookup
- Domain input
- Record type selector (A, AAAA, MX, TXT, CNAME, NS, SOA)
- DNS server selector (System, Cloudflare, Google, Custom)
- Query time display
- Results with TTL

#### 3.4.5 WHOIS Lookup
- Domain or IP input
- Parsed results display
- Raw WHOIS data view
- Registrar information
- Expiration date
- Name servers

#### 3.4.6 Speed Test
- Download speed test
- Upload speed test
- Latency/Ping measurement
- Server selection
- Progress indicator
- Historical results graph
- Compare with previous tests

#### 3.4.7 Wake on LAN
- Device selector (from discovered devices)
- Manual MAC address input
- Broadcast address configuration
- Send magic packet
- Status feedback

#### 3.4.8 Bonjour Browser
- Service type filter
- Discovered services list
- Service details (name, type, domain, host, port)
- TXT record data
- Resolve service to IP

### 3.5 Settings

#### 3.5.1 General Settings
- Start at login
- Menu bar icon option
- Default monitoring interval
- Data retention period
- Theme (System/Light/Dark)

#### 3.5.2 Notifications
- Enable/disable notifications
- Alert on target down
- Alert on high latency threshold
- Alert on packet loss threshold
- Alert on new device discovered
- Sound settings

#### 3.5.3 Network Settings
- Public IP check service URL
- MAC vendor database updates
- Proxy configuration
- Custom DNS servers

#### 3.5.4 Companion App Settings
- Enable companion connection
- Bonjour service name
- CloudKit sync toggle
- Connected devices list
- Pairing management

#### 3.5.5 Data Management
- Export all data
- Import configuration
- Clear historical data
- Reset to defaults

### 3.6 Menu Bar Integration
- Mini status display
- Quick access to key stats
- Start/Stop monitoring
- Recent alerts
- Open main window

---

## 4. UI Layout & Navigation

### 4.1 Window Structure
```
┌─────────────────────────────────────────────────────────────┐
│  Traffic Lights   │        Window Title (Hidden)            │
├───────────────────┼─────────────────────────────────────────┤
│                   │                                         │
│    SIDEBAR        │           MAIN CONTENT AREA             │
│    (220px)        │                                         │
│                   │                                         │
│  ┌─────────────┐  │  ┌─────────────────────────────────┐   │
│  │ App Logo    │  │  │                                 │   │
│  │ NetMonitorv1.0 │  │  │   Content varies by section     │   │
│  └─────────────┘  │  │                                 │   │
│                   │  │   - Dashboard cards             │   │
│  Navigation:      │  │   - Split views for lists       │   │
│  ○ Dashboard      │  │   - Tool interfaces             │   │
│  ○ Targets        │  │                                 │   │
│  ○ Devices        │  │                                 │   │
│  ○ Tools          │  │                                 │   │
│  ○ Settings       │  │                                 │   │
│                   │  │                                 │   │
│  ┌─────────────┐  │  └─────────────────────────────────┘   │
│  │ Status:     │  │                                         │
│  │ ● Running   │  │                                         │
│  │ [Stop]      │  │                                         │
│  └─────────────┘  │                                         │
└───────────────────┴─────────────────────────────────────────┘
```

### 4.2 Navigation Flow
```
Sidebar Navigation (Always Visible)
    │
    ├── Dashboard ────────► Main monitoring overview
    │                       - Stats cards grid
    │                       - Target summary table
    │
    ├── Targets ──────────► Target list + detail split view
    │                       - Left: Target list with status
    │                       - Right: Selected target details/graphs
    │                       - Toolbar: Add, Edit, Delete, Refresh
    │
    ├── Devices ──────────► Device list + Network Map split view
    │                       - Left: Scrollable device list
    │                       - Right: Network topology OR device detail
    │                       - Toolbar: Scan, View toggle
    │
    ├── Tools ────────────► Tool grid + Tool runner split view
    │                       - Left: Tool cards grid (2 columns)
    │                       - Right: Selected tool interface
    │
    └── Settings ─────────► Settings categories
                            - Tab or list navigation
                            - Form-based configuration
```

### 4.3 Design System

#### Colors
- **Primary Accent**: Cyan (#06B6D4)
- **Background**: Dark gradient (Slate 950 → Blue 950)
- **Cards**: White @ 5% opacity with blur
- **Borders**: White @ 10% opacity
- **Text Primary**: White
- **Text Secondary**: White @ 60% opacity
- **Success**: Green (#10B981)
- **Warning**: Yellow (#F59E0B)
- **Error**: Red (#EF4444)

#### Typography
- **Headings**: SF Pro Display, Bold
- **Body**: SF Pro Text, Regular
- **Monospace**: SF Mono (for IPs, MACs, code output)

#### Components
- Glass-effect cards with subtle borders
- Rounded corners (12-16px for cards)
- Subtle shadows
- Consistent 8px spacing grid

---

## 5. Data Models

### 5.1 Core Models

```swift
struct MonitoringSession {
    let id: UUID
    let startedAt: Date
    var stoppedAt: Date?
    var isRunning: Bool
}

struct NetworkTarget: Identifiable {
    let id: UUID
    var name: String
    var host: String
    var port: Int?
    var protocol: TargetProtocol
    var checkInterval: TimeInterval
    var timeout: TimeInterval
    var isEnabled: Bool
    var createdAt: Date
}

struct TargetStatistics {
    let targetId: UUID
    let timestamp: Date
    let latency: Double?
    let isReachable: Bool
    let errorMessage: String?
}

struct LocalDevice: Identifiable {
    let id: UUID
    var ipAddress: String
    var macAddress: String
    var hostname: String?
    var vendor: String?
    var deviceType: DeviceType
    var customName: String?
    var notes: String?
    var firstSeen: Date
    var lastSeen: Date
    var isOnline: Bool
}

struct ConnectionInfo {
    let type: ConnectionType
    let ssid: String?
    let signalStrength: Int?
    let channel: Int?
    let frequency: String?
    let linkSpeed: String?
    let gatewayIP: String?
    let gatewayMAC: String?
}

struct ISPInfo {
    let publicIP: String
    let ispName: String
    let asn: String
    let city: String?
    let country: String?
    let updatedAt: Date
}
```

---

## 6. Companion App Communication

### 6.1 Local Network Sync (Bonjour)
- Advertise service: `_netmon._tcp`
- Port: 8849
- JSON-based message protocol
- Real-time data push to companion
- Accept commands from companion (run tool, refresh)

### 6.2 Data Shared with Companion
- Current connection info
- Gateway info
- ISP info
- Target list with current status
- Local devices list
- Tool results (when requested)

### 6.3 CloudKit Sync (Optional)
- Sync target configurations
- Sync device custom names/notes
- Historical statistics (last 24 hours)

---

## 7. Error Handling

- Network unreachable states
- Permission denied handling
- Graceful degradation when services unavailable
- User-friendly error messages
- Retry mechanisms with exponential backoff
- Logging for debugging

---

## 8. Performance Requirements

- Dashboard refresh: Real-time (1 second intervals)
- Target checks: Configurable (5-60 seconds)
- Device scan: < 30 seconds for /24 subnet
- Memory usage: < 150MB typical
- CPU usage: < 5% during active monitoring
- Startup time: < 2 seconds

---

## 9. Future Considerations

- Multiple network profiles
- VPN detection and info
- Bandwidth monitoring per device
- Alert automation (webhooks, scripts)
- Plugin/extension system
- Multi-window support
- Network traffic analysis
