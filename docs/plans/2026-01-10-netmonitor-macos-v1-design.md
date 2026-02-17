# NetMonitor macOS v1.0 - Architecture Design

**Date:** 2026-01-10
**Scope:** macOS v1.0 with Dashboard, Target Monitoring, and Companion Communication
**Platform:** macOS 15.0+, Swift 6, SwiftUI + SwiftData

---

## Executive Summary

NetMonitor macOS v1.0 is a professional network monitoring application that provides real-time target monitoring, local device discovery, and companion app communication. The application follows modern Swift 6 patterns with strict concurrency, @Observable state management, SwiftData persistence, and AsyncStream-based monitoring.

### Version 1.0 Scope
- **Dashboard:** Real-time network status, session tracking, quick stats
- **Target Monitoring:** ICMP/HTTP/HTTPS checks with historical statistics
- **Device Discovery:** Local network scanning with visual topology map
- **Companion Communication:** Bonjour-based protocol for iOS companion app
- **Tools:** Deferred to v1.1 (basic ping/DNS only if time permits)

### iOS Companion
Built in parallel but **after** macOS v1.0 validates the communication protocol. macOS establishes the data contract that iOS will consume.

---

## Project Structure

### Workspace Architecture
```
NetMonitor.xcworkspace/
├── NetMonitorShared/           (Swift Package)
│   ├── Communication/
│   │   ├── BonjourService.swift
│   │   ├── Messages.swift
│   │   └── MessageTypes.swift
│   └── Common/
│       └── Enums.swift
│
├── NetMonitor-macOS/           (macOS App Target)
│   ├── Models/                 (SwiftData)
│   ├── Services/               (Monitoring protocols)
│   ├── Views/                  (SwiftUI)
│   └── App/
│
└── NetMonitor-iOS/             (iOS App Target - built later)
    └── (TBD after macOS v1.0)
```

### NetMonitorShared Package
- **Purpose:** Type-safe communication between macOS and iOS
- **Contains:** JSON message types, Bonjour service protocol, shared enums
- **Dependencies:** None (pure Swift, no SwiftUI/SwiftData)
- **Benefits:** Compiler-enforced consistency, shared communication contract

### Platform-Specific Models
- **macOS:** Rich SwiftData models optimized for detailed time-series storage
- **iOS:** Lightweight SwiftData models optimized for battery/memory efficiency
- **Mapping:** Each platform translates between local models and shared message types

---

## Modern Swift Standards

Following the 2025/2026 iOS/macOS development best practices:

### State Management
- ✅ `@Observable` classes (NOT `ObservableObject`/`@Published`)
- ✅ `@MainActor` for all state management classes
- ✅ `@State` for ownership (NOT `@StateObject`)
- ✅ `@Bindable` for creating bindings from observable objects

### Persistence
- ✅ SwiftData with `@Model` macro (NOT Core Data)
- ✅ `@Query` for synchronous UI-driven fetches
- ✅ Implicit autosave (no manual `context.save()`)
- ✅ Background cleanup via `PersistentIdentifier` + separate context

### Concurrency
- ✅ Swift 6 strict concurrency mode enabled
- ✅ Actors for background work (monitoring, scanning, network services)
- ✅ `async/await` for asynchronous operations
- ✅ `AsyncStream` for event streams (replacing Combine publishers)
- ✅ `Sendable` conformance for cross-actor data

### Architecture
- ✅ "View is the ViewModel" - minimal MVVM ceremony
- ✅ `@Observable` state holders for complex logic only
- ✅ Direct `@Query` in views (no repository wrappers)
- ✅ NavigationStack with value-based navigation

---

## Data Models (SwiftData)

### NetworkTarget
```swift
@Model
final class NetworkTarget {
    var id: UUID
    var name: String
    var host: String
    var port: Int?
    var `protocol`: TargetProtocol  // ICMP, HTTP, HTTPS, TCP
    var checkInterval: TimeInterval
    var timeout: TimeInterval
    var isEnabled: Bool
    var createdAt: Date

    // Relationship
    @Relationship(deleteRule: .cascade)
    var measurements: [TargetMeasurement]
}

enum TargetProtocol: String, Codable, CaseIterable {
    case icmp, http, https, tcp
}
```

### TargetMeasurement
```swift
@Model
final class TargetMeasurement {
    var targetID: UUID
    var timestamp: Date
    var latency: Double?        // nil when check fails
    var isReachable: Bool        // explicit success/failure
    var errorMessage: String?    // human-readable error
}
```

**Design decisions:**
- Store ALL check attempts (success and failure) as data points
- Failed checks are measurements, not exceptions
- No pre-calculated aggregates - compute on-demand with @Query
- Retain 24-48 hours, prune older data via background task
- Simple types for SwiftData compatibility

### LocalDevice
```swift
@Model
final class LocalDevice {
    var id: UUID
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

enum DeviceType: String, Codable, CaseIterable {
    case phone, laptop, tablet, tv, speaker
    case gaming, iot, router, printer, unknown
}
```

### MonitoringSession
```swift
@Model
final class MonitoringSession {
    var id: UUID
    var startedAt: Date
    var pausedAt: Date?
    var stoppedAt: Date?
    var isActive: Bool
}
```

---

## Monitoring Architecture

### Core Pattern: AsyncStream + Actors

**@MainActor @Observable class MonitoringSession**
- UI-facing state holder
- Properties: `isMonitoring: Bool`, `startTime: Date?`, `targetResults: [UUID: TargetMeasurement]`
- Methods: `startMonitoring(targets:)`, `stopMonitoring()`, `pauseMonitoring()`
- Creates one Task per enabled target
- Consumes AsyncStream from each TargetMonitor
- Updates `targetResults` dictionary → SwiftUI views observe and redraw

**Actor TargetMonitor**
- Background monitoring logic
- Static method: `monitor(target: NetworkTarget) -> AsyncStream<TargetMeasurement>`
- Yields measurement every `checkInterval` seconds
- Uses appropriate NetworkMonitorService based on protocol type
- Respects Task cancellation for clean shutdown

### Data Flow
```
User taps "Start Monitoring"
    ↓
MonitoringSession.startMonitoring()
    ↓
For each enabled target:
    Task {
        for await measurement in TargetMonitor.monitor(target) {
            targetResults[target.id] = measurement
            saveToSwiftData(measurement)
        }
    }
    ↓
SwiftUI views observe targetResults → UI updates automatically
```

### Protocol-Based Monitor Services

```swift
protocol NetworkMonitorService {
    func check(target: NetworkTarget) async throws -> TargetMeasurement
}

actor ICMPMonitorService: NetworkMonitorService {
    // CFSocket wrapper for raw ICMP packets
    // Full control: packet construction, sequence numbers, TTL
}

actor HTTPMonitorService: NetworkMonitorService {
    // URLSession with HEAD request
    // Validates HTTP status code (200-299 = success)
    // Measures total request/response time
}

actor TCPMonitorService: NetworkMonitorService {
    // NWConnection for TCP socket checks
    // Connects to port, measures time to establish
}
```

**Design decisions:**
- ICMP via CFSocket (full control, custom packets)
- HTTP via URLSession HEAD request (validates service health, not just connectivity)
- Protocol abstraction enables easy testing and future protocol additions

---

## Statistics Calculation

### Time Windows
- 2 minutes
- 10 minutes
- All-time (session or last 24 hours)

### Metrics
- Latency: min, avg, max
- Jitter: variation in latency
- Packet loss: percentage of failed checks
- Uptime: percentage of successful checks

### Implementation Pattern
```swift
// SwiftUI view queries raw measurements
@Query(filter: #Predicate<TargetMeasurement> { measurement in
    measurement.targetID == targetID &&
    measurement.timestamp > Date.now.addingTimeInterval(-120)
})
var last2MinMeasurements: [TargetMeasurement]

// Calculate stats in-memory (fast for small arrays)
var statistics: Statistics {
    StatisticsCalculator.calculate(measurements: last2MinMeasurements)
}
```

**Why this works:**
- Small data sets (2-10 min of checks = 24-120 data points)
- In-memory calculation is microseconds
- SwiftData @Query is indexed and lazy
- No schema complexity with aggregate tables
- Flexible - can add new time windows without migrations

---

## Device Discovery

### Hybrid Scanning Strategy

**Phase 1: Quick Scan (instant)**
- Parse system ARP table (`arp -a`)
- Returns devices that have communicated recently
- Immediate UI feedback

**Phase 2: Full Scan (background, 20-30s)**
- Active ping sweep across subnet (e.g., 192.168.1.1-254)
- Discovers all devices, including quiet ones
- Progress updates via AsyncStream

**Phase 3: Continuous Discovery**
- Bonjour/mDNS service browser runs continuously
- Discovers services as they announce
- Updates device list in real-time

### Implementation
```swift
actor DeviceScanner {
    func quickScan() async -> [LocalDevice] {
        // Parse ARP table, return immediately
    }

    func fullScan() -> AsyncStream<LocalDevice> {
        AsyncStream { continuation in
            Task {
                for ip in subnet {
                    if let device = await pingAndDiscover(ip) {
                        continuation.yield(device)
                    }
                }
                continuation.finish()
            }
        }
    }

    func startBonjourDiscovery() -> AsyncStream<BonjourDevice>
}
```

**UX Flow:**
1. User opens Devices tab → instant results from ARP
2. Background scan populates more devices over 20-30s
3. Devices "appear" as discovered (feels alive)
4. Manual "Scan" button triggers fresh full scan

---

## macOS UI Architecture

### App Structure
```swift
@main
struct NetMonitorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: [
                    NetworkTarget.self,
                    TargetMeasurement.self,
                    LocalDevice.self,
                    MonitoringSession.self
                ])
        }
        Settings {
            SettingsView()
        }
    }
}
```

### ContentView: NavigationSplitView
```swift
struct ContentView: View {
    @State private var selectedSection: Section? = .dashboard

    var body: some View {
        NavigationSplitView {
            // Sidebar (220px)
            SidebarView(selection: $selectedSection)
        } detail: {
            // Detail pane swaps based on selection
            switch selectedSection {
            case .dashboard: DashboardView()
            case .targets: TargetsView()
            case .devices: DevicesView()
            case .tools: ToolsView()
            case .settings: SettingsView()
            }
        }
    }
}

enum Section: String, CaseIterable {
    case dashboard, targets, devices, tools, settings
}
```

### Dashboard View
- Scrollable VStack of glass-effect cards
- Cards: Session Info, Connection Details, Gateway, ISP, Quick Stats
- Live data from `@Environment(MonitoringSession.self)`
- Glass effect: `.background(.ultraThinMaterial)` + rounded corners + borders

### Targets View (Split)
- **Left pane:** List of targets with status indicators
- **Right pane:** Selected target detail
  - Swift Charts: Latency graph, packet loss chart
  - Statistics tables (2min/10min/all-time)
  - Actions: Edit, Delete, Pause
- Toolbar: Add new target button

### Devices View (Split)
- **Left pane:** Device list (Table or List)
- **Right pane:** Network map OR device detail (toggle)
- **Network Map:** Canvas with radial topology
  - Gateway at center
  - Devices positioned around gateway
  - Color-coded status (green/gray/red)
  - Interactive: tap device to select

### Design System
- **Colors:** Cyan accent (#06B6D4), dark gradient background
- **Glass cards:** White @ 5% opacity + ultraThinMaterial + 10% border
- **Typography:** SF Pro Display (headings), SF Pro Text (body), SF Mono (IPs/MACs)
- **Spacing:** 8px grid, 12-16px rounded corners

---

## Companion Communication

### Bonjour Service

**Actor BonjourService** (in NetMonitorShared)
- Advertises `_netmon._tcp` service on port 8849
- Methods: `startAdvertising()`, `stopAdvertising()`, `send(message:to:)`
- Property: `messageStream: AsyncStream<IncomingMessage>`
- Handles multiple iOS clients simultaneously

**@MainActor @Observable class ConnectionManager** (in macOS app)
- Property: `connectedDevices: [ConnectedDevice]`
- Property: `isAdvertising: Bool`
- Consumes `BonjourService.messageStream`
- Handles incoming requests from iOS
- Pushes updates to connected clients

### Message Protocol (JSON)

**macOS → iOS (push updates):**
```swift
struct NetworkStatusMessage: Codable, Sendable {
    let ssid: String?
    let signalStrength: Int?
    let gatewayIP: String?
    let gatewayMAC: String?
    let publicIP: String?
    let ispName: String?
    let timestamp: Date
}

struct TargetListMessage: Codable, Sendable {
    let targets: [TargetSnapshot]
}

struct DeviceListMessage: Codable, Sendable {
    let devices: [DeviceSnapshot]
}

struct TargetSnapshot: Codable, Sendable {
    let id: UUID
    let name: String
    let host: String
    let isOnline: Bool
    let currentLatency: Double?
}
```

**iOS → macOS (requests):**
```swift
enum IncomingMessage: Codable, Sendable {
    case requestStatus
    case requestTargets
    case requestDevices
    case refreshData
}
```

### Data Flow
1. iOS discovers Mac via Bonjour browsing
2. iOS connects and sends `requestStatus`
3. macOS maps SwiftData models → Codable message types
4. macOS sends `NetworkStatusMessage`
5. iOS receives, maps to its own SwiftData models
6. Periodic push: macOS sends updates every 5-10 seconds while connected

### CloudKit Sync
**Deferred to v1.1.** For v1.0, we validate the Bonjour protocol first. CloudKit adds remote access when not on same network.

---

## Development Phases

### Phase 1: Foundation
- Create Xcode workspace + macOS app target
- Add NetMonitorShared Swift package
- SwiftData models with relationships
- NavigationSplitView shell + sidebar navigation
- Swift 6 strict concurrency enabled

**Deliverable:** App launches, sidebar navigates, SwiftData container initialized

### Phase 2: Core Monitoring Engine
- MonitoringSession with AsyncStream pattern
- ICMPMonitorService (CFSocket wrapper)
- HTTPMonitorService (URLSession)
- Test: Start monitoring → measurements stored to SwiftData
- Basic Dashboard showing live results

**Deliverable:** Can monitor targets, see live latency updates

### Phase 3: Target Management
- Targets view: add/edit/delete functionality
- Default targets pre-populated (Gateway, 1.1.1.1, 8.8.8.8)
- Statistics calculations (2min/10min/all-time)
- Swift Charts: latency graph

**Deliverable:** Full target management with historical graphs

### Phase 4: Device Discovery
- DeviceScanner actor (ARP + active scan + Bonjour)
- Devices view: list + network map
- Canvas radial topology visualization
- Device detail sheets

**Deliverable:** Can scan network, visualize topology

### Phase 5: Companion Communication
- BonjourService in NetMonitorShared
- ConnectionManager on macOS
- Message encoding/sending
- Test with simple iOS harness app

**Deliverable:** macOS can advertise and send data to iOS test app

### Phase 6: Polish & Testing
- Settings view with preferences
- Error handling and edge cases
- Background cleanup (prune old measurements)
- Accessibility identifiers
- Performance testing

**Deliverable:** Production-ready v1.0

---

## Technical Constraints

### Platform Requirements
- macOS 15.0+ (Sonoma)
- Swift 6 strict concurrency mode
- SwiftUI (no AppKit unless absolutely necessary)
- SwiftData (no Core Data)

### Performance Targets
- Dashboard refresh: 1 second intervals
- Target check: Configurable 5-60 seconds
- Device scan: < 30 seconds for /24 subnet
- Memory: < 150MB typical
- CPU: < 5% during monitoring
- Startup: < 2 seconds

### Permissions Required
- Local Network access (NSLocalNetworkUsageDescription)
- Outgoing network connections

---

## Testing Strategy

### Unit Tests
- Monitor services with mocked network responses
- Statistics calculations with known datasets
- Message encoding/decoding
- Device scanner with mocked ARP data

### Integration Tests
- MonitoringSession lifecycle (start/stop/pause)
- SwiftData persistence and queries
- Bonjour service advertising/discovery

### UI Tests
- Navigation flows
- Target CRUD operations
- Device list updates
- Accessibility identifiers for all interactive elements

### Performance Tests
- Monitoring 50+ targets simultaneously
- Large measurement datasets (24 hours)
- Network map with 100+ devices

---

## Future Considerations (v1.1+)

- Network Tools (Ping, Traceroute, Port Scanner, DNS Lookup, WHOIS, Speed Test)
- CloudKit sync for remote access
- Menu bar integration
- Advanced alerting/notifications
- Multiple monitoring profiles
- VPN detection
- Export/reporting features

---

## Summary

NetMonitor macOS v1.0 is a modern, Swift 6-native network monitoring application built on @Observable state management, SwiftData persistence, and AsyncStream-based monitoring. The architecture supports parallel iOS development through a shared communication package while keeping persistence models platform-optimized. The phased development approach validates each layer before proceeding, ensuring a solid foundation for future enhancements.
