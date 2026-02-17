# NetMonitor iOS Companion - Product Requirements Document

## 1. Project Overview

### 1.1 Product Name
NetMonitor Companion for iOS

### 1.2 Description
A mobile companion app for NetMonitor macOS that provides remote network monitoring, on-device network diagnostics, and local device scanning capabilities. The app displays data synced from the macOS app while also performing independent network analysis from the iOS device's perspective.

### 1.3 Target Platform
- iOS 18.0 and later
- iPadOS 18.0 and later
- Native SwiftUI application
- Optimized for iPhone (primary) and iPad

### 1.4 Target Users
- NetMonitor macOS users wanting mobile access
- IT professionals monitoring networks remotely
- Users performing on-device network diagnostics

### 1.5 Design Language
- iOS 26 Liquid Glass design aesthetic
- Glassmorphism with translucent materials
- Vibrant blur effects
- Fluid animations and transitions

---

## 2. Technical Requirements

### 2.1 Frameworks & Technologies
- **UI**: SwiftUI with iOS 26 glass materials
- **Networking**: Network.framework, NWPathMonitor
- **Local Discovery**: MultipeerConnectivity, Bonjour/mDNS
- **Companion Communication**: Bonjour local network + CloudKit
- **Data Persistence**: SwiftData
- **Background Tasks**: BGTaskScheduler for periodic checks
- **Widgets**: WidgetKit for home screen widgets
- **Charts**: Swift Charts

### 2.2 Architecture
- MVVM architecture pattern
- Protocol-oriented network services
- Combine for reactive data flow
- Dependency injection

### 2.3 Permissions Required
- Local Network access (required for device discovery and Mac connection)
- Location (When in Use - for WiFi SSID)
- Background App Refresh
- Notifications

---

## 3. Feature Specifications

### 3.1 Connection Modes

#### 3.1.1 Paired Mode (Connected to Mac)
- Auto-discover NetMonitor Mac on local network via Bonjour
- Real-time data sync from Mac
- Remote tool execution on Mac
- Full monitoring data access

#### 3.1.2 Standalone Mode
- Independent network monitoring from iOS device
- On-device WiFi analysis
- Local network device scanning
- Built-in network tools
- No Mac connection required

#### 3.1.3 Remote Mode (CloudKit)
- Access Mac data when not on same network
- View last synced statistics
- Historical data access
- Push notifications for alerts

### 3.2 Dashboard Screen

#### 3.2.1 Header Section
- App name and connection status
- Paired Mac indicator (connected/disconnected)
- Last sync timestamp

#### 3.2.2 Session Card
- Monitoring session start time
- Running duration
- Data source indicator (Mac/Local)

#### 3.2.3 WiFi Connection Card
- Network SSID
- Signal strength (visual bars + dBm)
- Frequency band (2.4/5/6 GHz)
- Channel number
- Security type
- BSSID (Access Point MAC)

#### 3.2.4 Gateway Card
- Gateway IP address
- Gateway MAC address
- Vendor name
- Latency to gateway

#### 3.2.5 ISP Card
- Public IP address
- ISP provider name
- ASN
- Location (City, Country)
- Refresh button

#### 3.2.6 Target Summary Card
- Online/Offline targets count
- Visual status indicators
- Average latency
- Tap to navigate to Targets tab
- Quick list of top 6 targets with status

#### 3.2.7 Local Devices Card
- Device count on network
- Last scan timestamp
- Scan button
- Tap to navigate to Devices/Map tab

### 3.3 Network Map Screen

#### 3.3.1 Visual Topology
- Radial network map with gateway at center
- Device nodes arranged around gateway
- Animated connection lines (dashed)
- Pulsing animation on gateway
- Color-coded status:
  - Green: Active
  - Gray: Idle
  - Red: Offline

#### 3.3.2 Device Nodes
- Icon based on device type
- Tap to select and show details
- Visual highlight on selection

#### 3.3.3 Device List (Below Map)
- Scrollable list of all devices
- Device icon, name, IP address
- Status badge
- Tap to view device details

#### 3.3.4 Device Detail Sheet (Modal)
- Device name (editable)
- Device type icon
- IP address
- MAC address
- Vendor
- Status indicator
- First seen / Last seen timestamps
- Action buttons:
  - Ping
  - Wake on LAN (if supported)
  - View Details
  - Copy Info

#### 3.3.5 Scan Controls
- Pull-to-refresh for quick scan
- Scan button in header
- Scan progress indicator
- Last scan timestamp

### 3.4 Tools Screen

#### 3.4.1 Tools Grid Layout
Tools organized by category with colored icons:

**Diagnostic Tools**
- Ping
- Traceroute
- DNS Lookup

**Scanning Tools**
- Port Scanner
- Bonjour Discovery

**Performance Tools**
- Speed Test

**Information Tools**
- WHOIS Lookup

**Control Tools**
- Wake on LAN

#### 3.4.2 Tool Card Design
- Colored icon container
- Tool name
- Brief description
- Tap to open tool

#### 3.4.3 Quick Actions Section
- Scan Local Network (button)
- Run Speed Test (button)
- Check Gateway (button)

#### 3.4.4 Recent Activity Section
- Last 5 tool executions
- Tool name, target, result summary
- Timestamp
- Tap to view full results

### 3.5 Individual Tool Interfaces

#### 3.5.1 Ping Tool
**Input:**
- Host/IP text field
- Packet count stepper (1-100)
- Continuous toggle

**Output:**
- Real-time results list
- Each ping: seq, time, TTL
- Statistics summary
- Stop button (for continuous)

#### 3.5.2 Traceroute Tool
**Input:**
- Host/IP text field
- Max hops stepper

**Output:**
- Hop-by-hop results
- Hop number, IP, hostname, latency
- Progress indicator
- Visual path (optional)

#### 3.5.3 Port Scanner
**Input:**
- Host/IP text field
- Port range picker or presets:
  - Common ports
  - Web ports
  - Custom range

**Output:**
- Open ports list
- Port number, service name, status
- Scan progress indicator

#### 3.5.4 DNS Lookup
**Input:**
- Domain text field
- Record type picker (A, AAAA, MX, TXT, etc.)
- DNS server picker

**Output:**
- Query results
- TTL values
- Query time

#### 3.5.5 Bonjour Discovery
**Input:**
- Service type filter (optional)
- Search/filter field

**Output:**
- Discovered services list
- Service name, type, domain
- Tap for details (host, port, TXT records)

#### 3.5.6 Speed Test
**Interface:**
- Large speedometer gauge
- Download speed (primary)
- Upload speed (secondary)
- Ping/Latency
- Start button
- Progress animation

**Results:**
- Download Mbps
- Upload Mbps
- Ping ms
- Server used
- Timestamp
- Compare with previous

#### 3.5.7 WHOIS Lookup
**Input:**
- Domain/IP text field

**Output:**
- Parsed WHOIS data
- Registrar, dates, name servers
- Raw data toggle

#### 3.5.8 Wake on LAN
**Input:**
- Device picker (from discovered)
- Manual MAC entry option

**Action:**
- Send magic packet
- Status feedback
- History of wake attempts

### 3.6 Settings Screen

#### 3.6.1 Connection Settings
- Paired Mac management
- Manual pairing option
- CloudKit sync toggle
- Connection status

#### 3.6.2 Monitoring Settings
- Auto-refresh interval
- Background refresh toggle
- Data source preference (Mac/Local/Auto)

#### 3.6.3 Notifications
- Enable/disable all
- Target down alerts
- High latency alerts
- New device discovered
- Threshold configuration

#### 3.6.4 Appearance
- Theme (System/Light/Dark)
- App icon selection
- Accent color (future)

#### 3.6.5 Data & Privacy
- Clear cached data
- Export data
- Privacy policy link

#### 3.6.6 About
- App version
- Build number
- Acknowledgements
- Support link
- Rate app

### 3.7 Widgets

#### 3.7.1 Small Widget
- Network status (Online/Offline)
- Current WiFi name
- Signal strength indicator

#### 3.7.2 Medium Widget
- WiFi name and signal
- Gateway latency
- Online targets count
- Public IP

#### 3.7.3 Large Widget
- Full connection summary
- Target status list (top 5)
- Device count
- Last updated timestamp

---

## 4. UI Layout & Navigation

### 4.1 Tab Bar Structure
```
┌─────────────────────────────────────────┐
│                                         │
│            CONTENT AREA                 │
│                                         │
│   (Scrollable content per tab)          │
│                                         │
│                                         │
├─────────────────────────────────────────┤
│  ┌───────┐ ┌───────┐ ┌───────┐         │
│  │       │ │       │ │       │         │
│  │ Dash  │ │  Map  │ │ Tools │  (3 tabs)
│  │ board │ │       │ │       │         │
│  └───────┘ └───────┘ └───────┘         │
└─────────────────────────────────────────┘
```

### 4.2 Screen Hierarchy

```
Tab Bar
├── Dashboard Tab
│   └── Dashboard Screen (scrollable)
│       ├── Session Card
│       ├── WiFi Card
│       ├── Gateway Card
│       ├── ISP Card
│       ├── Targets Summary Card
│       └── Local Devices Card
│
├── Map Tab
│   └── Network Map Screen
│       ├── Visual Topology (top half)
│       ├── Device List (bottom half)
│       └── Device Detail Sheet (modal)
│           ├── Device Info
│           └── Action Buttons
│
└── Tools Tab
    └── Tools Screen
        ├── Tools Grid
        ├── Quick Actions
        └── Recent Activity
        │
        └── Tool Detail Sheets (modal)
            ├── Tool Header
            ├── Input Fields
            ├── Run Button
            └── Results Area
```

### 4.3 Navigation Patterns

- **Tab switching**: Bottom tab bar (3 tabs)
- **Detail views**: Modal sheets (`.sheet` modifier)
- **Tool execution**: Full-screen modal or sheet
- **Settings**: Accessible via gear icon in Dashboard header
- **Pull-to-refresh**: Dashboard and Device list

### 4.4 iOS 26 Glass Design Implementation

#### Glass Card Style
```swift
.background(.ultraThinMaterial)
.background(Color.white.opacity(0.1))
.clipShape(RoundedRectangle(cornerRadius: 20))
.overlay(
    RoundedRectangle(cornerRadius: 20)
        .stroke(Color.white.opacity(0.2), lineWidth: 1)
)
.shadow(color: .black.opacity(0.1), radius: 10)
```

#### Color Palette
- **Background**: Dynamic gradient (slate-900 → blue-900)
- **Glass cards**: White @ 10% + ultraThinMaterial
- **Borders**: White @ 20%
- **Primary accent**: Cyan (#06B6D4)
- **Success**: Emerald (#10B981)
- **Warning**: Amber (#F59E0B)
- **Error**: Red (#EF4444)
- **Text primary**: White
- **Text secondary**: White @ 60%

#### Typography
- **Large titles**: .largeTitle, Bold
- **Card headers**: .headline
- **Body text**: .subheadline
- **Captions**: .caption, secondary color
- **Monospace**: .system(.body, design: .monospaced)

---

## 5. Data Models

### 5.1 Core Models

```swift
// Connection to Mac
struct PairedMac: Identifiable, Codable {
    let id: UUID
    var name: String
    var lastConnected: Date
    var isConnected: Bool
}

// Synced from Mac or local
struct NetworkStatus: Codable {
    let connectionType: ConnectionType
    let ssid: String?
    let signalStrength: Int?
    let signalDBm: Int?
    let channel: Int?
    let frequency: String?
    let bssid: String?
    let securityType: String?
    let gatewayIP: String?
    let gatewayMAC: String?
    let gatewayVendor: String?
    let gatewayLatency: Double?
    let publicIP: String?
    let ispName: String?
    let asn: String?
    let updatedAt: Date
}

struct MonitoringTarget: Identifiable, Codable {
    let id: UUID
    var name: String
    var host: String
    var `protocol`: TargetProtocol
    var currentLatency: Double?
    var isOnline: Bool
    var lastChecked: Date
}

struct LocalDevice: Identifiable, Codable {
    let id: UUID
    var ipAddress: String
    var macAddress: String
    var hostname: String?
    var vendor: String?
    var deviceType: DeviceType
    var customName: String?
    var status: DeviceStatus
    var firstSeen: Date
    var lastSeen: Date
}

enum DeviceType: String, Codable, CaseIterable {
    case phone, laptop, tablet, tv, speaker
    case gaming, iot, router, printer, unknown
    
    var iconName: String { ... }
}

enum DeviceStatus: String, Codable {
    case active, idle, offline
}

struct ToolResult: Identifiable, Codable {
    let id: UUID
    let toolType: ToolType
    let target: String
    let timestamp: Date
    let success: Bool
    let summary: String
    let details: String
}
```

---

## 6. Mac Communication Protocol

### 6.1 Bonjour Discovery
- Service type: `_netmon._tcp`
- Browse for services on local network
- Auto-connect to known paired Macs

### 6.2 Connection Flow
```
1. iOS app browses for _netmon._tcp services
2. User selects Mac to pair (first time) or auto-connects
3. Exchange pairing handshake
4. Establish persistent connection
5. Mac pushes data updates
6. iOS can request tool execution
```

### 6.3 Message Types (JSON)

**Mac → iOS:**
- `statusUpdate`: Full network status
- `targetUpdate`: Target status changes
- `deviceUpdate`: Device list changes
- `toolResult`: Tool execution results

**iOS → Mac:**
- `requestStatus`: Request full status
- `runTool`: Execute tool on Mac
- `ping`: Connection keepalive

### 6.4 CloudKit Sync (Remote Mode)
- Sync configuration (targets, preferences)
- Push recent statistics
- Store last-known status for offline viewing

---

## 7. Background & Notifications

### 7.1 Background Tasks
- Periodic status check (when Mac connected via CloudKit)
- Background fetch for widget updates
- Silent push notification handling

### 7.2 Push Notifications
- Target down alert
- Target recovered alert
- High latency warning
- New device on network
- Mac connection lost

### 7.3 Local Notifications
- Tool completion (when app backgrounded)
- Scan complete

---

## 8. Error Handling

### 8.1 Connection Errors
- Mac not found on network
- Connection lost to Mac
- CloudKit unavailable
- Network unavailable

### 8.2 Permission Errors
- Local network access denied
- Location access denied

### 8.3 User Feedback
- Clear error messages
- Retry options
- Settings shortcuts for permissions
- Graceful degradation (standalone mode)

---

## 9. Performance Requirements

- App launch: < 1 second to interactive
- Dashboard load: < 0.5 seconds
- Network scan: < 20 seconds for /24
- Memory usage: < 100MB typical
- Battery efficient (< 2% per hour monitoring)
- Smooth 60fps animations

---

## 10. Accessibility

- VoiceOver support for all screens
- Dynamic Type support
- Sufficient color contrast
- Haptic feedback for actions
- Reduce Motion support

---

## 11. App Store Requirements

### 11.1 Privacy
- Privacy manifest for Network APIs
- No third-party analytics (or disclosed)
- Local data storage preference

### 11.2 Required Descriptions
- Local Network usage description
- Location usage description
- Background refresh description

---

## 12. Future Considerations

- Apple Watch companion app
- Shortcuts/Siri integration
- Live Activities for ongoing monitoring
- Interactive widgets
- CarPlay integration (status view)
- Multiple Mac connections
- Network profiles
- Export/share reports
