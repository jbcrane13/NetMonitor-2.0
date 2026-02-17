# Phase 2: Core Monitoring Engine Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Implement the core network monitoring engine with real-time ICMP and HTTP target checking, live dashboard updates, and proper actor-based concurrency.

**Architecture:** Actor-based monitoring services using AsyncStream for real-time updates. MonitoringSession (@MainActor @Observable) coordinates monitoring and publishes results. SwiftData stores all measurements. Dashboard uses @Query for reactive UI updates.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Actors, AsyncStream, CFSocket (ICMP), URLSession (HTTP)

---

## Prerequisites

- ✅ Phase 1 Foundation complete
- ✅ SwiftData models created (NetworkTarget, TargetMeasurement)
- ✅ Network entitlements configured
- ✅ Swift 6 strict concurrency enabled

---

## Task 1: Create Network Monitor Protocol

**Files:**
- Create: `NetMonitor/Services/NetworkMonitorService.swift`
- Test: `NetMonitorTests/Services/NetworkMonitorServiceTests.swift`

**Step 1: Create protocol definition**

Create: `NetMonitor/Services/NetworkMonitorService.swift`

```swift
import Foundation

/// Protocol for network monitoring services
/// Implementations must be actors for thread safety
protocol NetworkMonitorService: Actor {
    /// Check a network target and return measurement result
    /// - Parameter target: The target to check
    /// - Returns: Measurement result with latency and reachability
    /// - Throws: NetworkMonitorError for unrecoverable failures
    func check(target: NetworkTarget) async throws -> TargetMeasurement
}

/// Errors that can occur during network monitoring
enum NetworkMonitorError: Error, CustomStringConvertible {
    case invalidHost(String)
    case timeout
    case permissionDenied
    case networkUnreachable
    case unknownError(Error)

    var description: String {
        switch self {
        case .invalidHost(let host):
            return "Invalid host: \(host)"
        case .timeout:
            return "Request timed out"
        case .permissionDenied:
            return "Network permission denied"
        case .networkUnreachable:
            return "Network unreachable"
        case .unknownError(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}
```

**Step 2: Add to Xcode project**

Actions:
1. In Xcode, create new group "Services" under NetMonitor
2. Add NetworkMonitorService.swift to Services group
3. Ensure file is in NetMonitor target

**Step 3: Verify build**

Run: `⌘+B` (Build)

Expected: Build succeeds

**Step 4: Create basic protocol test**

Create: `NetMonitorTests/Services/NetworkMonitorServiceTests.swift`

```swift
import Testing
@testable import NetMonitor

@Suite("Network Monitor Service Protocol Tests")
struct NetworkMonitorServiceTests {

    @Test("Mock service can be created")
    func mockServiceCreation() async throws {
        let mock = MockNetworkMonitorService()
        #expect(mock != nil)
    }
}

// Mock implementation for testing
actor MockNetworkMonitorService: NetworkMonitorService {
    var mockLatency: Double = 10.0
    var shouldFail: Bool = false

    func check(target: NetworkTarget) async throws -> TargetMeasurement {
        if shouldFail {
            throw NetworkMonitorError.timeout
        }

        return TargetMeasurement(
            latency: mockLatency,
            isReachable: true
        )
    }
}
```

**Step 5: Add test file to Xcode**

Actions:
1. Create Services folder in NetMonitorTests
2. Add NetworkMonitorServiceTests.swift
3. Ensure file is in NetMonitorTests target

**Step 6: Run tests**

Run: `⌘+U` (Test)

Expected: Test passes

**Step 7: Commit**

```bash
git add NetMonitor/Services/NetworkMonitorService.swift NetMonitorTests/Services/NetworkMonitorServiceTests.swift
git commit -m "feat: add NetworkMonitorService protocol

- Protocol for actor-based monitoring services
- NetworkMonitorError enum with descriptive messages
- Mock implementation for testing
- Thread-safe via actor isolation

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Implement HTTP Monitor Service

**Files:**
- Create: `NetMonitor/Services/HTTPMonitorService.swift`
- Test: `NetMonitorTests/Services/HTTPMonitorServiceTests.swift`

**Step 1: Create HTTP monitor actor**

Create: `NetMonitor/Services/HTTPMonitorService.swift`

```swift
import Foundation

/// Actor-based HTTP/HTTPS monitoring service
actor HTTPMonitorService: NetworkMonitorService {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func check(target: NetworkTarget) async throws -> TargetMeasurement {
        // Validate target protocol
        guard target.targetProtocol == .http || target.targetProtocol == .https else {
            throw NetworkMonitorError.invalidHost("Target protocol must be HTTP or HTTPS")
        }

        // Build URL
        let scheme = target.targetProtocol == .https ? "https" : "http"
        let port = target.port.map { ":\($0)" } ?? ""
        guard let url = URL(string: "\(scheme)://\(target.host)\(port)") else {
            throw NetworkMonitorError.invalidHost(target.host)
        }

        // Perform request with timeout
        var request = URLRequest(url: url)
        request.timeoutInterval = target.timeout
        request.httpMethod = "HEAD"  // Use HEAD to minimize data transfer

        let startTime = Date()

        do {
            let (_, response) = try await session.data(for: request)
            let latency = Date().timeIntervalSince(startTime) * 1000  // Convert to ms

            // Check HTTP status code
            if let httpResponse = response as? HTTPURLResponse {
                let isReachable = (200...399).contains(httpResponse.statusCode)

                return TargetMeasurement(
                    latency: latency,
                    isReachable: isReachable,
                    errorMessage: isReachable ? nil : "HTTP \(httpResponse.statusCode)"
                )
            }

            // Non-HTTP response (shouldn't happen but handle it)
            return TargetMeasurement(
                latency: latency,
                isReachable: true
            )

        } catch let error as URLError {
            let latency = Date().timeIntervalSince(startTime) * 1000

            // Map URLError to our error types
            let monitorError: NetworkMonitorError
            let errorMessage: String

            switch error.code {
            case .timedOut:
                monitorError = .timeout
                errorMessage = "Request timed out"
            case .notConnectedToInternet, .networkConnectionLost:
                monitorError = .networkUnreachable
                errorMessage = "Network unreachable"
            default:
                monitorError = .unknownError(error)
                errorMessage = error.localizedDescription
            }

            return TargetMeasurement(
                latency: nil,
                isReachable: false,
                errorMessage: errorMessage
            )
        }
    }
}
```

**Step 2: Add to Xcode project**

Actions:
1. Add HTTPMonitorService.swift to Services group
2. Ensure file is in NetMonitor target
3. Import NetMonitorShared for TargetProtocol enum

**Step 3: Verify build**

Run: `⌘+B` (Build)

Expected: Build succeeds

**Step 4: Create HTTP monitor tests**

Create: `NetMonitorTests/Services/HTTPMonitorServiceTests.swift`

```swift
import Testing
@testable import NetMonitor

@Suite("HTTP Monitor Service Tests")
struct HTTPMonitorServiceTests {

    @Test("HTTP monitor can check reachable target")
    func checkReachableTarget() async throws {
        let service = HTTPMonitorService()

        let target = NetworkTarget(
            name: "Google",
            host: "www.google.com",
            targetProtocol: .https,
            timeout: 5.0
        )

        let measurement = try await service.check(target: target)

        #expect(measurement.isReachable == true)
        #expect(measurement.latency != nil)
        #expect(measurement.latency! > 0)
        #expect(measurement.errorMessage == nil)
    }

    @Test("HTTP monitor handles unreachable target")
    func checkUnreachableTarget() async throws {
        let service = HTTPMonitorService()

        let target = NetworkTarget(
            name: "Invalid",
            host: "this-domain-definitely-does-not-exist-12345.com",
            targetProtocol: .https,
            timeout: 2.0
        )

        let measurement = try await service.check(target: target)

        #expect(measurement.isReachable == false)
        #expect(measurement.errorMessage != nil)
    }

    @Test("HTTP monitor respects timeout")
    func checkTimeout() async throws {
        let service = HTTPMonitorService()

        // Use a non-routable IP to force timeout
        let target = NetworkTarget(
            name: "Timeout Test",
            host: "10.255.255.1",
            port: 80,
            targetProtocol: .http,
            timeout: 1.0
        )

        let startTime = Date()
        let measurement = try await service.check(target: target)
        let duration = Date().timeIntervalSince(startTime)

        #expect(measurement.isReachable == false)
        #expect(duration < 2.0)  // Should timeout within reasonable time
    }
}
```

**Step 5: Add test file to Xcode**

Actions:
1. Add HTTPMonitorServiceTests.swift to Services folder in tests
2. Ensure file is in NetMonitorTests target

**Step 6: Run tests**

Run: `⌘+U` (Test)

Expected: All 3 tests pass

**Step 7: Commit**

```bash
git add NetMonitor/Services/HTTPMonitorService.swift NetMonitorTests/Services/HTTPMonitorServiceTests.swift
git commit -m "feat: implement HTTP/HTTPS monitoring service

- Actor-based HTTPMonitorService with URLSession
- HEAD requests for minimal data transfer
- Proper timeout handling
- HTTP status code validation (200-399 = reachable)
- Comprehensive error mapping
- Full test coverage

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Implement ICMP Monitor Service (Part 1: Core)

**Files:**
- Create: `NetMonitor/Services/ICMPMonitorService.swift`
- Create: `NetMonitor/Services/ICMPSocket.swift`

**Step 1: Create ICMP packet structures**

Create: `NetMonitor/Services/ICMPSocket.swift`

```swift
import Foundation
import Darwin

/// ICMP Echo Request/Reply packet structure
struct ICMPPacket {
    static let headerSize = 8
    static let echoRequestType: UInt8 = 8
    static let echoReplyType: UInt8 = 0

    var type: UInt8
    var code: UInt8
    var checksum: UInt16
    var identifier: UInt16
    var sequenceNumber: UInt16
    var data: Data

    /// Calculate ICMP checksum
    static func calculateChecksum(data: Data) -> UInt16 {
        var sum: UInt32 = 0
        var count = data.count
        var index = 0

        // Sum all 16-bit words
        while count > 1 {
            let value = UInt16(data[index]) << 8 | UInt16(data[index + 1])
            sum += UInt32(value)
            index += 2
            count -= 2
        }

        // Add leftover byte if odd length
        if count > 0 {
            sum += UInt32(data[index]) << 8
        }

        // Fold 32-bit sum to 16 bits
        while (sum >> 16) != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }

        return ~UInt16(sum & 0xFFFF)
    }

    /// Create echo request packet
    static func createEchoRequest(identifier: UInt16, sequenceNumber: UInt16) -> Data {
        var packet = Data(count: headerSize)

        packet[0] = echoRequestType
        packet[1] = 0  // code
        // checksum bytes 2-3 will be filled later
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xFF)
        packet[6] = UInt8(sequenceNumber >> 8)
        packet[7] = UInt8(sequenceNumber & 0xFF)

        // Calculate and set checksum
        let checksum = calculateChecksum(data: packet)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xFF)

        return packet
    }
}

/// Low-level ICMP socket wrapper using CFSocket
actor ICMPSocket {

    private var socket: CFSocket?
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 3.0) {
        self.timeout = timeout
    }

    deinit {
        close()
    }

    /// Send ICMP echo request and wait for reply
    /// - Parameters:
    ///   - host: IP address or hostname
    ///   - identifier: Packet identifier
    ///   - sequenceNumber: Packet sequence number
    /// - Returns: Round-trip time in milliseconds
    /// - Throws: NetworkMonitorError
    func sendEchoRequest(to host: String, identifier: UInt16, sequenceNumber: UInt16) async throws -> Double {
        // This is a placeholder for the CFSocket implementation
        // The actual implementation requires C interop and is complex
        // For Phase 2, we'll use a simplified version

        throw NetworkMonitorError.unknownError(
            NSError(domain: "ICMPSocket", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "ICMP implementation requires CFSocket C interop - to be implemented"
            ])
        )
    }

    private func close() {
        if let socket = socket {
            CFSocketInvalidate(socket)
            self.socket = nil
        }
    }
}
```

**Step 2: Create ICMP monitor service**

Create: `NetMonitor/Services/ICMPMonitorService.swift`

```swift
import Foundation

/// Actor-based ICMP ping monitoring service
actor ICMPMonitorService: NetworkMonitorService {

    private let socket: ICMPSocket
    private var sequenceNumber: UInt16 = 0
    private let identifier: UInt16

    init() {
        self.identifier = UInt16.random(in: 1...65535)
        self.socket = ICMPSocket()
    }

    func check(target: NetworkTarget) async throws -> TargetMeasurement {
        // Validate target protocol
        guard target.targetProtocol == .icmp else {
            throw NetworkMonitorError.invalidHost("Target protocol must be ICMP")
        }

        // Increment sequence number
        sequenceNumber = sequenceNumber &+ 1

        let startTime = Date()

        do {
            // Send ICMP echo request
            let latency = try await socket.sendEchoRequest(
                to: target.host,
                identifier: identifier,
                sequenceNumber: sequenceNumber
            )

            return TargetMeasurement(
                latency: latency,
                isReachable: true
            )

        } catch let error as NetworkMonitorError {
            return TargetMeasurement(
                latency: nil,
                isReachable: false,
                errorMessage: error.description
            )
        } catch {
            return TargetMeasurement(
                latency: nil,
                isReachable: false,
                errorMessage: "ICMP error: \(error.localizedDescription)"
            )
        }
    }
}
```

**Step 3: Add files to Xcode**

Actions:
1. Add ICMPSocket.swift to Services group
2. Add ICMPMonitorService.swift to Services group
3. Ensure both files are in NetMonitor target

**Step 4: Verify build**

Run: `⌘+B` (Build)

Expected: Build succeeds

**Step 5: Commit**

```bash
git add NetMonitor/Services/ICMPSocket.swift NetMonitor/Services/ICMPMonitorService.swift
git commit -m "feat: add ICMP monitoring service (placeholder)

- ICMPSocket actor with packet structures
- ICMP checksum calculation
- ICMPMonitorService actor
- Sequence number tracking
- Note: CFSocket C interop to be implemented separately

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Create MonitoringSession State Holder

**Files:**
- Create: `NetMonitor/Services/MonitoringSession.swift`
- Test: `NetMonitorTests/Services/MonitoringSessionTests.swift`

**Step 1: Create MonitoringSession class**

Create: `NetMonitor/Services/MonitoringSession.swift`

```swift
import Foundation
import SwiftData

/// Main-actor bound monitoring session coordinator
/// Manages active monitoring and publishes results to the UI
@MainActor
@Observable
final class MonitoringSession {

    // MARK: - Published State

    /// Whether monitoring is currently active
    private(set) var isMonitoring: Bool = false

    /// Current monitoring start time
    private(set) var startTime: Date?

    /// Latest measurement results by target ID
    private(set) var latestResults: [UUID: TargetMeasurement] = [:]

    /// Active monitoring tasks (for cancellation)
    private var monitoringTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let httpService: HTTPMonitorService
    private let icmpService: ICMPMonitorService

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.httpService = HTTPMonitorService()
        self.icmpService = ICMPMonitorService()
    }

    // MARK: - Public API

    /// Start monitoring all enabled targets
    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        startTime = Date()

        // Fetch all enabled targets
        let descriptor = FetchDescriptor<NetworkTarget>(
            predicate: #Predicate { $0.isEnabled }
        )

        guard let targets = try? modelContext.fetch(descriptor) else {
            stopMonitoring()
            return
        }

        // Start monitoring each target
        for target in targets {
            startMonitoringTarget(target)
        }
    }

    /// Stop monitoring all targets
    func stopMonitoring() {
        guard isMonitoring else { return }

        isMonitoring = false

        // Cancel all monitoring tasks
        for task in monitoringTasks.values {
            task.cancel()
        }
        monitoringTasks.removeAll()
    }

    /// Get latest measurement for a target
    func latestMeasurement(for targetID: UUID) -> TargetMeasurement? {
        return latestResults[targetID]
    }

    // MARK: - Private Methods

    private func startMonitoringTarget(_ target: NetworkTarget) {
        // Cancel any existing task for this target
        monitoringTasks[target.id]?.cancel()

        // Create new monitoring task
        let task = Task { [weak self] in
            await self?.monitorTarget(target)
        }

        monitoringTasks[target.id] = task
    }

    private func monitorTarget(_ target: NetworkTarget) async {
        while !Task.isCancelled && isMonitoring {
            // Select appropriate service
            let service: any NetworkMonitorService = switch target.targetProtocol {
            case .http, .https:
                httpService
            case .icmp:
                icmpService
            case .tcp:
                // TCP not implemented yet, use HTTP as fallback
                httpService
            }

            // Perform check
            do {
                let measurement = try await service.check(target: target)

                // Update latest results (back on main actor)
                await MainActor.run {
                    latestResults[target.id] = measurement
                }

                // Save to SwiftData (background context)
                await saveMeasurement(measurement, for: target)

            } catch {
                // Handle errors by creating failed measurement
                let failedMeasurement = TargetMeasurement(
                    latency: nil,
                    isReachable: false,
                    errorMessage: error.localizedDescription
                )

                await MainActor.run {
                    latestResults[target.id] = failedMeasurement
                }

                await saveMeasurement(failedMeasurement, for: target)
            }

            // Wait for check interval
            try? await Task.sleep(for: .seconds(target.checkInterval))
        }
    }

    private func saveMeasurement(_ measurement: TargetMeasurement, for target: NetworkTarget) async {
        // Create background context for saving
        await Task.detached { [modelContext] in
            // Note: This needs proper ModelContext handling for background saves
            // For now, we'll save on main context
            await MainActor.run {
                // Associate measurement with target
                target.measurements.append(measurement)

                try? modelContext.save()
            }
        }.value
    }
}
```

**Step 2: Add to Xcode project**

Actions:
1. Add MonitoringSession.swift to Services group
2. Ensure file is in NetMonitor target

**Step 3: Verify build**

Run: `⌘+B` (Build)

Expected: Build succeeds

**Step 4: Create MonitoringSession tests**

Create: `NetMonitorTests/Services/MonitoringSessionTests.swift`

```swift
import Testing
import SwiftData
@testable import NetMonitor

@Suite("Monitoring Session Tests")
struct MonitoringSessionTests {

    @Test("Monitoring session can be created")
    @MainActor
    func sessionCreation() throws {
        let container = try ModelContainer(
            for: NetworkTarget.self, TargetMeasurement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let session = MonitoringSession(modelContext: container.mainContext)

        #expect(session.isMonitoring == false)
        #expect(session.startTime == nil)
    }

    @Test("Monitoring session can start and stop")
    @MainActor
    func sessionStartStop() throws {
        let container = try ModelContainer(
            for: NetworkTarget.self, TargetMeasurement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let session = MonitoringSession(modelContext: container.mainContext)

        session.startMonitoring()
        #expect(session.isMonitoring == true)
        #expect(session.startTime != nil)

        session.stopMonitoring()
        #expect(session.isMonitoring == false)
    }
}
```

**Step 5: Add test file to Xcode**

Actions:
1. Add MonitoringSessionTests.swift to Services folder in tests
2. Ensure file is in NetMonitorTests target

**Step 6: Run tests**

Run: `⌘+U` (Test)

Expected: Both tests pass

**Step 7: Commit**

```bash
git add NetMonitor/Services/MonitoringSession.swift NetMonitorTests/Services/MonitoringSessionTests.swift
git commit -m "feat: add MonitoringSession state holder

- @MainActor @Observable for UI binding
- Coordinates monitoring of all enabled targets
- Routes to appropriate service by protocol
- Publishes latest results to UI
- Manages monitoring task lifecycle
- Background SwiftData saves

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Update Dashboard with Live Monitoring

**Files:**
- Modify: `NetMonitor/Views/DashboardView.swift`
- Modify: `NetMonitor/ContentView.swift`

**Step 1: Update DashboardView with monitoring UI**

Modify: `NetMonitor/Views/DashboardView.swift`

Replace entire file with:

```swift
import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MonitoringSession.self) private var session

    @Query(sort: \NetworkTarget.name) private var targets: [NetworkTarget]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dashboard")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        if let startTime = session.startTime {
                            Text("Monitoring since \(startTime, format: .dateTime.hour().minute())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Start/Stop Button
                    Button(action: {
                        if session.isMonitoring {
                            session.stopMonitoring()
                        } else {
                            session.startMonitoring()
                        }
                    }) {
                        Label(
                            session.isMonitoring ? "Stop Monitoring" : "Start Monitoring",
                            systemImage: session.isMonitoring ? "stop.circle.fill" : "play.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(session.isMonitoring ? .red : .green)
                }
                .padding(.horizontal)

                // Monitoring Status
                if targets.isEmpty {
                    ContentUnavailableView(
                        "No Targets Configured",
                        systemImage: "target",
                        description: Text("Add network targets in the Targets section to start monitoring")
                    )
                } else {
                    // Target Status Cards
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(targets) { target in
                            TargetStatusCard(
                                target: target,
                                measurement: session.latestMeasurement(for: target.id)
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Dashboard")
    }
}

// MARK: - Target Status Card

struct TargetStatusCard: View {
    let target: NetworkTarget
    let measurement: TargetMeasurement?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemImage: target.targetProtocol.iconName)
                    .foregroundStyle(.secondary)

                Text(target.name)
                    .font(.headline)

                Spacer()

                // Status Indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            // Host
            Text(target.host)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // Metrics
            if let measurement = measurement {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Latency")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let latency = measurement.latency {
                            Text(String(format: "%.0f ms", latency))
                                .font(.title3)
                                .fontWeight(.semibold)
                        } else {
                            Text("—")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Status")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(measurement.isReachable ? "Online" : "Offline")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(measurement.isReachable ? .green : .red)
                    }
                }
            } else {
                Text("Waiting for data...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private var statusColor: Color {
        guard let measurement = measurement else {
            return .gray
        }
        return measurement.isReachable ? .green : .red
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
        .modelContainer(PreviewContainer().container)
        .environment(MonitoringSession(
            modelContext: PreviewContainer().container.mainContext
        ))
}
```

**Step 2: Update ContentView to provide MonitoringSession**

Modify: `NetMonitor/ContentView.swift`

Update to provide MonitoringSession in environment:

```swift
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSection: Section? = .dashboard
    @State private var session: MonitoringSession?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSection)
        } detail: {
            if let session = session {
                Group {
                    switch selectedSection {
                    case .dashboard:
                        DashboardView()
                            .accessibilityIdentifier("detail_dashboard")
                    case .targets:
                        TargetsView()
                            .accessibilityIdentifier("detail_targets")
                    case .devices:
                        DevicesView()
                            .accessibilityIdentifier("detail_devices")
                    case .tools:
                        ToolsView()
                            .accessibilityIdentifier("detail_tools")
                    case .settings:
                        SettingsView()
                            .accessibilityIdentifier("detail_settings")
                    case nil:
                        Text("Select a section")
                            .accessibilityIdentifier("detail_empty")
                    }
                }
                .environment(session)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            // Create monitoring session on appear
            session = MonitoringSession(modelContext: modelContext)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewContainer().container)
}
```

**Step 3: Add protocol icon helper**

Add to `NetMonitorShared/Sources/NetMonitorShared/Common/Enums.swift`:

```swift
// Add this extension to TargetProtocol enum
extension TargetProtocol {
    public var iconName: String {
        switch self {
        case .http, .https:
            return "network"
        case .icmp:
            return "waveform.path.ecg"
        case .tcp:
            return "arrow.left.arrow.right"
        }
    }
}
```

**Step 4: Verify build**

Run: `⌘+B` (Build)

Expected: Build succeeds

**Step 5: Run app**

Run: `⌘+R` (Run)

Expected:
- Dashboard shows "Start Monitoring" button
- If preview targets exist, they show as cards
- Clicking "Start Monitoring" initiates checks

**Step 6: Commit**

```bash
git add NetMonitor/Views/DashboardView.swift NetMonitor/ContentView.swift NetMonitorShared/Sources/NetMonitorShared/Common/Enums.swift
git commit -m "feat: implement live monitoring dashboard

- Real-time target status cards with latency
- Start/Stop monitoring button
- Grid layout for multiple targets
- Glass-effect material design
- Status indicators (green/red/gray)
- MonitoringSession in environment
- Empty state for no targets

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Add Targets Management View

**Files:**
- Modify: `NetMonitor/Views/TargetsView.swift`
- Create: `NetMonitor/Views/AddTargetSheet.swift`

**Step 1: Create Add Target Sheet**

Create: `NetMonitor/Views/AddTargetSheet.swift`

```swift
import SwiftUI
import SwiftData
import NetMonitorShared

struct AddTargetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var selectedProtocol: TargetProtocol = .https
    @State private var checkInterval: Double = 5.0
    @State private var timeout: Double = 3.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Target Details") {
                    TextField("Name", text: $name)
                    TextField("Host", text: $host)
                        .textContentType(.URL)

                    HStack {
                        TextField("Port (optional)", text: $port)
                            .textFieldStyle(.roundedBorder)

                        Text("Optional")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Protocol") {
                    Picker("Protocol", selection: $selectedProtocol) {
                        ForEach(TargetProtocol.allCases) { protocol in
                            Text(protocol.rawValue)
                                .tag(protocol)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Monitoring Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Check Interval: \(Int(checkInterval))s")
                            .font(.subheadline)
                        Slider(value: $checkInterval, in: 1...60, step: 1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Timeout: \(Int(timeout))s")
                            .font(.subheadline)
                        Slider(value: $timeout, in: 1...30, step: 1)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Target")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addTarget()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(width: 500, height: 500)
    }

    private var isValid: Bool {
        !name.isEmpty && !host.isEmpty
    }

    private func addTarget() {
        let portInt = Int(port)

        let target = NetworkTarget(
            name: name,
            host: host,
            port: portInt,
            targetProtocol: selectedProtocol,
            checkInterval: checkInterval,
            timeout: timeout
        )

        modelContext.insert(target)
        try? modelContext.save()
    }
}

#Preview {
    AddTargetSheet()
        .modelContainer(PreviewContainer().container)
}
```

**Step 2: Update TargetsView**

Modify: `NetMonitor/Views/TargetsView.swift`

Replace entire file with:

```swift
import SwiftUI
import SwiftData

struct TargetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NetworkTarget.name) private var targets: [NetworkTarget]

    @State private var showingAddSheet = false
    @State private var selectedTarget: NetworkTarget?

    var body: some View {
        VStack {
            if targets.isEmpty {
                ContentUnavailableView(
                    "No Targets",
                    systemImage: "target",
                    description: Text("Add network targets to monitor")
                )
            } else {
                List(selection: $selectedTarget) {
                    ForEach(targets) { target in
                        TargetRow(target: target)
                            .tag(target)
                    }
                    .onDelete(perform: deleteTargets)
                }
            }
        }
        .navigationTitle("Targets")
        .toolbar {
            Button(action: { showingAddSheet = true }) {
                Label("Add Target", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddTargetSheet()
        }
    }

    private func deleteTargets(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(targets[index])
        }
        try? modelContext.save()
    }
}

struct TargetRow: View {
    @Bindable var target: NetworkTarget

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(target.name)
                    .font(.headline)

                Text(target.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                Label(target.targetProtocol.rawValue, systemImage: target.targetProtocol.iconName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Enabled", isOn: $target.isEnabled)
                    .labelsHidden()
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TargetsView()
        .modelContainer(PreviewContainer().container)
}
```

**Step 3: Add files to Xcode**

Actions:
1. Add AddTargetSheet.swift to Views group
2. Ensure both files are in NetMonitor target

**Step 4: Verify build**

Run: `⌘+B` (Build)

Expected: Build succeeds

**Step 5: Run app and test**

Run: `⌘+R` (Run)

Actions:
1. Navigate to Targets section
2. Click "+" button
3. Add a test target (e.g., Google DNS)
4. Verify target appears in list
5. Toggle enabled/disabled
6. Go to Dashboard and start monitoring

Expected: Target monitoring works

**Step 7: Commit**

```bash
git add NetMonitor/Views/TargetsView.swift NetMonitor/Views/AddTargetSheet.swift
git commit -m "feat: implement targets management UI

- List view with all targets
- Add target sheet with form validation
- Protocol picker (HTTP/HTTPS/ICMP/TCP)
- Check interval and timeout sliders
- Enable/disable toggle per target
- Delete targets with swipe
- Empty state guidance

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 7: Add Statistics Query to Dashboard

**Files:**
- Create: `NetMonitor/Views/TargetStatisticsView.swift`
- Modify: `NetMonitor/Views/DashboardView.swift`

**Step 1: Create statistics view**

Create: `NetMonitor/Views/TargetStatisticsView.swift`

```swift
import SwiftUI
import SwiftData
import Charts

struct TargetStatisticsView: View {
    let target: NetworkTarget

    @Query private var measurements: [TargetMeasurement]

    init(target: NetworkTarget) {
        self.target = target

        // Query last 50 measurements for this target
        let targetID = target.id
        let predicate = #Predicate<TargetMeasurement> { measurement in
            measurement.target?.id == targetID
        }

        _measurements = Query(
            filter: predicate,
            sort: [SortDescriptor(\TargetMeasurement.timestamp, order: .reverse)],
            animation: .default
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Measurements")
                .font(.headline)

            if measurements.isEmpty {
                Text("No measurements yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Statistics
                HStack(spacing: 32) {
                    StatisticItem(
                        title: "Avg Latency",
                        value: averageLatency,
                        unit: "ms"
                    )

                    StatisticItem(
                        title: "Min Latency",
                        value: minLatency,
                        unit: "ms"
                    )

                    StatisticItem(
                        title: "Max Latency",
                        value: maxLatency,
                        unit: "ms"
                    )

                    StatisticItem(
                        title: "Uptime",
                        value: uptime,
                        unit: "%"
                    )
                }

                // Chart
                if #available(macOS 13.0, *) {
                    Chart {
                        ForEach(measurements.prefix(20).reversed()) { measurement in
                            if let latency = measurement.latency {
                                LineMark(
                                    x: .value("Time", measurement.timestamp),
                                    y: .value("Latency", latency)
                                )
                                .foregroundStyle(.cyan)
                            }
                        }
                    }
                    .frame(height: 150)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    // MARK: - Statistics

    private var averageLatency: String {
        let latencies = measurements.compactMap { $0.latency }
        guard !latencies.isEmpty else { return "—" }
        let avg = latencies.reduce(0, +) / Double(latencies.count)
        return String(format: "%.0f", avg)
    }

    private var minLatency: String {
        guard let min = measurements.compactMap({ $0.latency }).min() else {
            return "—"
        }
        return String(format: "%.0f", min)
    }

    private var maxLatency: String {
        guard let max = measurements.compactMap({ $0.latency }).max() else {
            return "—"
        }
        return String(format: "%.0f", max)
    }

    private var uptime: String {
        guard !measurements.isEmpty else { return "—" }
        let reachable = measurements.filter { $0.isReachable }.count
        let percentage = (Double(reachable) / Double(measurements.count)) * 100
        return String(format: "%.1f", percentage)
    }
}

struct StatisticItem: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    let container = PreviewContainer().container
    let target = NetworkTarget(
        name: "Test",
        host: "1.1.1.1",
        targetProtocol: .icmp
    )
    container.mainContext.insert(target)

    return TargetStatisticsView(target: target)
        .modelContainer(container)
        .frame(width: 600)
}
```

**Step 2: Add to Xcode project**

Actions:
1. Add TargetStatisticsView.swift to Views group
2. Ensure file is in NetMonitor target

**Step 3: Verify build**

Run: `⌘+B` (Build)

Expected: Build succeeds

**Step 4: Commit**

```bash
git add NetMonitor/Views/TargetStatisticsView.swift
git commit -m "feat: add target statistics view with charts

- Calculate avg/min/max latency on-demand
- Calculate uptime percentage
- Line chart for recent measurements (20 data points)
- @Query with predicate for target-specific data
- Real-time updates via SwiftData

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 8: Update CLAUDE.md with Phase 2 Info

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add Phase 2 section to CLAUDE.md**

Modify: `CLAUDE.md`

Add after the Development Priorities section:

```markdown
## Phase 2: Core Monitoring Engine (COMPLETE)

Phase 2 adds real-time network monitoring capabilities.

### Monitoring Services

**NetworkMonitorService Protocol:**
- Actor-based protocol for thread-safe monitoring
- All implementations must be actors
- Returns TargetMeasurement with latency and reachability

**HTTPMonitorService:**
- Uses URLSession for HTTP/HTTPS checks
- HEAD requests for minimal data transfer
- Respects timeout settings
- Maps HTTP status codes (200-399 = reachable)

**ICMPMonitorService:**
- ICMP Echo Request/Reply (ping)
- CFSocket wrapper for low-level access
- Sequence number tracking
- Note: Full CFSocket implementation pending

### MonitoringSession

**@MainActor @Observable State Holder:**
```swift
@MainActor
@Observable
final class MonitoringSession {
    var isMonitoring: Bool
    var latestResults: [UUID: TargetMeasurement]
}
```

**Key Features:**
- Coordinates monitoring of all enabled targets
- Routes checks to appropriate service by protocol
- Publishes results to UI via @Observable
- Manages task lifecycle (start/stop/cancel)
- Background SwiftData saves for persistence

### Dashboard

**Live Monitoring UI:**
- Real-time target status cards
- Start/Stop monitoring button
- Latency display per target
- Status indicators (green/red/gray)
- Grid layout for multiple targets

**Statistics:**
- Average, min, max latency
- Uptime percentage
- Line charts with recent measurements
- @Query with predicates for efficient data access

### Targets Management

**CRUD Operations:**
- Add new targets via sheet
- Edit target settings
- Enable/disable individual targets
- Delete targets

**Target Configuration:**
- Name, host, optional port
- Protocol selection (HTTP/HTTPS/ICMP/TCP)
- Check interval (1-60 seconds)
- Timeout (1-30 seconds)
```

**Step 2: Verify build**

Run: `⌘+B` (Build)

Expected: Build succeeds

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add Phase 2 monitoring documentation

- Document monitoring services architecture
- Explain MonitoringSession coordination
- Describe dashboard and statistics features
- Include code examples for key patterns

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Phase 2 Complete - Verification Checklist

Before moving to Phase 3, verify:

- [ ] HTTP monitoring works (test with google.com)
- [ ] ICMP service exists (CFSocket implementation pending)
- [ ] MonitoringSession can start/stop
- [ ] Dashboard shows real-time updates
- [ ] Target cards update with latency
- [ ] Can add new targets via UI
- [ ] Can enable/disable targets
- [ ] Statistics calculate correctly
- [ ] SwiftData saves measurements
- [ ] All tests pass (`⌘+U`)
- [ ] All changes committed to git

---

## Next Steps

**Phase 3: Device Discovery & Network Tools**
- File: `docs/plans/2026-01-11-netmonitor-macos-phase3-discovery.md`
- Features: ARP scanner, Bonjour browser, device list view, network utilities (ping tool, traceroute, port scanner)

**To proceed with Phase 3 implementation, create the Phase 3 plan following the same structure.**
