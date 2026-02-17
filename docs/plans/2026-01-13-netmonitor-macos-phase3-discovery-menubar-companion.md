# Phase 3: Device Discovery, Menu Bar, and Companion App Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add local device discovery (ARP/Bonjour), menu bar integration with quick stats, and Bonjour-based companion app communication.

**Architecture:** Three actor-based services coordinate device discovery and companion communication. A menu bar extra provides persistent quick access. All services follow the existing protocol-oriented, actor-based patterns established in Phase 2.

**Tech Stack:** Network.framework, MultipeerConnectivity, NWBrowser, AppKit (NSStatusItem), SwiftData, Combine

---

## Table of Contents

1. [Task 1: Device Discovery Service Protocol](#task-1-device-discovery-service-protocol)
2. [Task 2: ARP Scanner Implementation](#task-2-arp-scanner-implementation)
3. [Task 3: Bonjour Discovery Service](#task-3-bonjour-discovery-service)
4. [Task 4: Device Discovery Coordinator](#task-4-device-discovery-coordinator)
5. [Task 5: MAC Vendor Lookup Service](#task-5-mac-vendor-lookup-service)
6. [Task 6: Devices View Implementation](#task-6-devices-view-implementation)
7. [Task 7: Device Detail View](#task-7-device-detail-view)
8. [Task 8: Menu Bar App Structure](#task-8-menu-bar-app-structure)
9. [Task 9: Menu Bar Status View](#task-9-menu-bar-status-view)
10. [Task 10: Menu Bar Quick Actions](#task-10-menu-bar-quick-actions)
11. [Task 11: Companion Protocol Definition](#task-11-companion-protocol-definition)
12. [Task 12: Companion Service Server](#task-12-companion-service-server)
13. [Task 13: Companion Message Handlers](#task-13-companion-message-handlers)
14. [Task 14: Integration and Testing](#task-14-integration-and-testing)

---

## Task 1: Device Discovery Service Protocol

Define the protocol contract for device discovery services.

**Files:**
- Create: `NetMonitor/Services/DeviceDiscoveryService.swift`
- Test: `NetMonitorTests/Services/DeviceDiscoveryServiceTests.swift`

**Step 1: Write the test file with protocol expectations**

```swift
// NetMonitorTests/Services/DeviceDiscoveryServiceTests.swift
import Testing
@testable import NetMonitor

@Suite("DeviceDiscoveryService Protocol Tests")
struct DeviceDiscoveryServiceTests {

    @Test("DiscoveredDevice contains required properties")
    func discoveredDeviceProperties() {
        let device = DiscoveredDevice(
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "test-device.local"
        )

        #expect(device.ipAddress == "192.168.1.100")
        #expect(device.macAddress == "AA:BB:CC:DD:EE:FF")
        #expect(device.hostname == "test-device.local")
    }

    @Test("DiscoveredDevice MAC address is normalized")
    func macAddressNormalized() {
        let device = DiscoveredDevice(
            ipAddress: "192.168.1.100",
            macAddress: "aa:bb:cc:dd:ee:ff",
            hostname: nil
        )

        #expect(device.macAddress == "AA:BB:CC:DD:EE:FF")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor test -only-testing:NetMonitorTests/DeviceDiscoveryServiceTests 2>&1 | head -50`
Expected: FAIL - DiscoveredDevice not defined

**Step 3: Write the protocol and DiscoveredDevice type**

```swift
// NetMonitor/Services/DeviceDiscoveryService.swift
import Foundation

/// Represents a device discovered on the local network
struct DiscoveredDevice: Sendable, Equatable {
    let ipAddress: String
    let macAddress: String
    let hostname: String?

    init(ipAddress: String, macAddress: String, hostname: String?) {
        self.ipAddress = ipAddress
        self.macAddress = macAddress.uppercased()
        self.hostname = hostname
    }
}

/// Errors that can occur during device discovery
enum DeviceDiscoveryError: Error, Sendable {
    case networkUnavailable
    case permissionDenied
    case scanTimeout
    case invalidSubnet
}

/// Protocol for device discovery services
protocol DeviceDiscoveryService: Actor {
    /// Scan the local network for devices
    func scanNetwork() async throws -> [DiscoveredDevice]

    /// Stop any ongoing scan
    func stopScan()

    /// Check if a scan is currently in progress
    var isScanning: Bool { get }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor test -only-testing:NetMonitorTests/DeviceDiscoveryServiceTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add NetMonitor/Services/DeviceDiscoveryService.swift NetMonitorTests/Services/DeviceDiscoveryServiceTests.swift
git commit -m "$(cat <<'EOF'
feat: add DeviceDiscoveryService protocol and DiscoveredDevice type

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: ARP Scanner Implementation

Implement ARP-based network scanning to discover devices on the local subnet.

**Files:**
- Create: `NetMonitor/Services/ARPScannerService.swift`
- Test: `NetMonitorTests/Services/ARPScannerServiceTests.swift`

**Step 1: Write the failing test**

```swift
// NetMonitorTests/Services/ARPScannerServiceTests.swift
import Testing
@testable import NetMonitor

@Suite("ARPScannerService Tests")
struct ARPScannerServiceTests {

    @Test("Scanner initializes with default timeout")
    func defaultTimeout() async {
        let scanner = ARPScannerService()
        let timeout = await scanner.timeout
        #expect(timeout == 30.0)
    }

    @Test("Scanner reports not scanning initially")
    func initialNotScanning() async {
        let scanner = ARPScannerService()
        let isScanning = await scanner.isScanning
        #expect(isScanning == false)
    }

    @Test("IP range calculation for /24 subnet")
    func ipRangeCalculation() {
        let range = ARPScannerService.calculateIPRange(
            baseIP: "192.168.1.0",
            subnetMask: "255.255.255.0"
        )

        #expect(range.count == 254) // .1 to .254
        #expect(range.first == "192.168.1.1")
        #expect(range.last == "192.168.1.254")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor test -only-testing:NetMonitorTests/ARPScannerServiceTests 2>&1 | head -50`
Expected: FAIL - ARPScannerService not defined

**Step 3: Write minimal ARPScannerService implementation**

```swift
// NetMonitor/Services/ARPScannerService.swift
import Foundation
import Network

/// ARP-based network scanner for discovering local devices
actor ARPScannerService: DeviceDiscoveryService {

    let timeout: TimeInterval
    private(set) var isScanning: Bool = false
    private var scanTask: Task<[DiscoveredDevice], Error>?

    init(timeout: TimeInterval = 30.0) {
        self.timeout = timeout
    }

    func scanNetwork() async throws -> [DiscoveredDevice] {
        guard !isScanning else { return [] }
        isScanning = true
        defer { isScanning = false }

        // Get local network info
        guard let (baseIP, subnetMask) = getLocalNetworkInfo() else {
            throw DeviceDiscoveryError.networkUnavailable
        }

        let ipRange = Self.calculateIPRange(baseIP: baseIP, subnetMask: subnetMask)
        var discoveredDevices: [DiscoveredDevice] = []

        // Scan IPs concurrently with limited parallelism
        await withTaskGroup(of: DiscoveredDevice?.self) { group in
            for ip in ipRange {
                group.addTask {
                    await self.probeIP(ip)
                }
            }

            for await device in group {
                if let device = device {
                    discoveredDevices.append(device)
                }
            }
        }

        return discoveredDevices
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    // MARK: - Private Methods

    private func getLocalNetworkInfo() -> (baseIP: String, subnetMask: String)? {
        // Use system calls to get network interface info
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // Look for en0 (WiFi) or en1 (Ethernet)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    var netmask = [CChar](repeating: 0, count: Int(NI_MAXHOST))

                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil, 0,
                        NI_NUMERICHOST
                    )

                    if let mask = interface.ifa_netmask {
                        getnameinfo(
                            mask,
                            socklen_t(mask.pointee.sa_len),
                            &netmask,
                            socklen_t(netmask.count),
                            nil, 0,
                            NI_NUMERICHOST
                        )
                    }

                    let ip = String(cString: hostname)
                    let mask = String(cString: netmask)

                    if !ip.isEmpty && !mask.isEmpty {
                        // Calculate base IP (network address)
                        let baseIP = calculateBaseIP(ip: ip, mask: mask)
                        return (baseIP, mask)
                    }
                }
            }
        }
        return nil
    }

    private func calculateBaseIP(ip: String, mask: String) -> String {
        let ipParts = ip.split(separator: ".").compactMap { Int($0) }
        let maskParts = mask.split(separator: ".").compactMap { Int($0) }

        guard ipParts.count == 4, maskParts.count == 4 else { return ip }

        let baseParts = zip(ipParts, maskParts).map { $0 & $1 }
        return baseParts.map(String.init).joined(separator: ".")
    }

    static func calculateIPRange(baseIP: String, subnetMask: String) -> [String] {
        let baseParts = baseIP.split(separator: ".").compactMap { Int($0) }
        let maskParts = subnetMask.split(separator: ".").compactMap { Int($0) }

        guard baseParts.count == 4, maskParts.count == 4 else { return [] }

        // For /24 subnet (255.255.255.0), scan .1 to .254
        // For simplicity, assume /24 subnet
        if maskParts[3] == 0 {
            let prefix = baseParts[0...2].map(String.init).joined(separator: ".")
            return (1...254).map { "\(prefix).\($0)" }
        }

        return []
    }

    private func probeIP(_ ip: String) async -> DiscoveredDevice? {
        // Create a TCP connection to probe the IP
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(ip),
            port: NWEndpoint.Port(rawValue: 80) ?? .http
        )

        let connection = NWConnection(to: endpoint, using: .tcp)

        return await withCheckedContinuation { continuation in
            var resolved = false

            connection.stateUpdateHandler = { state in
                guard !resolved else { return }

                switch state {
                case .ready, .preparing:
                    resolved = true
                    // Device is reachable - try to get MAC from ARP cache
                    let mac = self.getMACFromARPCache(ip: ip)
                    connection.cancel()
                    if let mac = mac {
                        continuation.resume(returning: DiscoveredDevice(
                            ipAddress: ip,
                            macAddress: mac,
                            hostname: nil
                        ))
                    } else {
                        continuation.resume(returning: nil)
                    }
                case .failed, .cancelled:
                    resolved = true
                    connection.cancel()
                    continuation.resume(returning: nil)
                default:
                    break
                }
            }

            connection.start(queue: .global())

            // Timeout after 1 second per IP
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                guard !resolved else { return }
                resolved = true
                connection.cancel()
                continuation.resume(returning: nil)
            }
        }
    }

    private nonisolated func getMACFromARPCache(ip: String) -> String? {
        // Read ARP cache via system command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-n", ip]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Parse ARP output: "? (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 ..."
                let pattern = "at ([0-9a-fA-F:]+)"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
                   let range = Range(match.range(at: 1), in: output) {
                    return String(output[range]).uppercased()
                }
            }
        } catch {
            // Ignore errors
        }
        return nil
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor test -only-testing:NetMonitorTests/ARPScannerServiceTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add NetMonitor/Services/ARPScannerService.swift NetMonitorTests/Services/ARPScannerServiceTests.swift
git commit -m "$(cat <<'EOF'
feat: add ARPScannerService for local network device discovery

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Bonjour Discovery Service

Implement Bonjour/mDNS service discovery to find advertised services.

**Files:**
- Create: `NetMonitor/Services/BonjourDiscoveryService.swift`
- Test: `NetMonitorTests/Services/BonjourDiscoveryServiceTests.swift`

**Step 1: Write the failing test**

```swift
// NetMonitorTests/Services/BonjourDiscoveryServiceTests.swift
import Testing
@testable import NetMonitor

@Suite("BonjourDiscoveryService Tests")
struct BonjourDiscoveryServiceTests {

    @Test("Service initializes with default service types")
    func defaultServiceTypes() async {
        let service = BonjourDiscoveryService()
        let types = await service.serviceTypes

        #expect(types.contains("_http._tcp"))
        #expect(types.contains("_ssh._tcp"))
        #expect(types.contains("_airplay._tcp"))
    }

    @Test("Service reports not scanning initially")
    func initialNotScanning() async {
        let service = BonjourDiscoveryService()
        let isScanning = await service.isScanning
        #expect(isScanning == false)
    }

    @Test("BonjourService struct contains required properties")
    func bonjourServiceProperties() {
        let service = BonjourService(
            name: "Test Service",
            type: "_http._tcp",
            domain: "local.",
            hostname: "test.local",
            port: 80,
            txtRecord: ["path": "/api"]
        )

        #expect(service.name == "Test Service")
        #expect(service.type == "_http._tcp")
        #expect(service.port == 80)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor test -only-testing:NetMonitorTests/BonjourDiscoveryServiceTests 2>&1 | head -50`
Expected: FAIL - BonjourDiscoveryService not defined

**Step 3: Write the BonjourDiscoveryService implementation**

```swift
// NetMonitor/Services/BonjourDiscoveryService.swift
import Foundation
import Network

/// Represents a discovered Bonjour service
struct BonjourService: Sendable, Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let domain: String
    let hostname: String?
    let port: Int?
    let txtRecord: [String: String]
    let ipAddress: String?

    init(
        name: String,
        type: String,
        domain: String = "local.",
        hostname: String? = nil,
        port: Int? = nil,
        txtRecord: [String: String] = [:],
        ipAddress: String? = nil
    ) {
        self.name = name
        self.type = type
        self.domain = domain
        self.hostname = hostname
        self.port = port
        self.txtRecord = txtRecord
        self.ipAddress = ipAddress
    }
}

/// Bonjour/mDNS service discovery
actor BonjourDiscoveryService {

    let serviceTypes: [String]
    private(set) var isScanning: Bool = false
    private(set) var discoveredServices: [BonjourService] = []

    private var browsers: [NWBrowser] = []

    init(serviceTypes: [String]? = nil) {
        self.serviceTypes = serviceTypes ?? [
            "_http._tcp",
            "_https._tcp",
            "_ssh._tcp",
            "_sftp._tcp",
            "_smb._tcp",
            "_afp._tcp",
            "_airplay._tcp",
            "_raop._tcp",
            "_printer._tcp",
            "_ipp._tcp",
            "_scanner._tcp",
            "_homekit._tcp",
            "_hap._tcp",
            "_companion-link._tcp",
            "_sleep-proxy._udp"
        ]
    }

    func startDiscovery() async {
        guard !isScanning else { return }
        isScanning = true
        discoveredServices = []

        for serviceType in serviceTypes {
            let browser = NWBrowser(
                for: .bonjour(type: serviceType, domain: "local."),
                using: .tcp
            )

            browser.stateUpdateHandler = { [weak self] state in
                Task { [weak self] in
                    await self?.handleBrowserState(state, type: serviceType)
                }
            }

            browser.browseResultsChangedHandler = { [weak self] results, changes in
                Task { [weak self] in
                    await self?.handleResults(results, type: serviceType)
                }
            }

            browser.start(queue: .global())
            browsers.append(browser)
        }
    }

    func stopDiscovery() {
        for browser in browsers {
            browser.cancel()
        }
        browsers.removeAll()
        isScanning = false
    }

    func scanNetwork() async throws -> [DiscoveredDevice] {
        await startDiscovery()

        // Wait for discovery to complete
        try await Task.sleep(for: .seconds(5))

        stopDiscovery()

        // Convert services to devices
        var devices: [DiscoveredDevice] = []
        var seenIPs = Set<String>()

        for service in discoveredServices {
            if let ip = service.ipAddress, !seenIPs.contains(ip) {
                seenIPs.insert(ip)
                devices.append(DiscoveredDevice(
                    ipAddress: ip,
                    macAddress: "", // Bonjour doesn't provide MAC
                    hostname: service.hostname
                ))
            }
        }

        return devices
    }

    // MARK: - Private Methods

    private func handleBrowserState(_ state: NWBrowser.State, type: String) {
        switch state {
        case .failed(let error):
            print("Bonjour browser failed for \(type): \(error)")
        case .cancelled:
            break
        default:
            break
        }
    }

    private func handleResults(_ results: Set<NWBrowser.Result>, type: String) {
        for result in results {
            switch result.endpoint {
            case .service(let name, let type, let domain, _):
                resolveService(name: name, type: type, domain: domain)
            default:
                break
            }
        }
    }

    private nonisolated func resolveService(name: String, type: String, domain: String) {
        let endpoint = NWEndpoint.service(
            name: name,
            type: type,
            domain: domain,
            interface: nil
        )

        let connection = NWConnection(to: endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = innerEndpoint {
                    let ipAddress: String?
                    switch host {
                    case .ipv4(let addr):
                        ipAddress = "\(addr)"
                    case .ipv6(let addr):
                        ipAddress = "\(addr)"
                    default:
                        ipAddress = nil
                    }

                    Task { [weak self] in
                        await self?.addService(BonjourService(
                            name: name,
                            type: type,
                            domain: domain,
                            hostname: nil,
                            port: Int(port.rawValue),
                            txtRecord: [:],
                            ipAddress: ipAddress
                        ))
                    }
                }
                connection.cancel()
            }
        }

        connection.start(queue: .global())

        // Cancel after timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            connection.cancel()
        }
    }

    private func addService(_ service: BonjourService) {
        // Avoid duplicates
        if !discoveredServices.contains(where: { $0.name == service.name && $0.type == service.type }) {
            discoveredServices.append(service)
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor test -only-testing:NetMonitorTests/BonjourDiscoveryServiceTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add NetMonitor/Services/BonjourDiscoveryService.swift NetMonitorTests/Services/BonjourDiscoveryServiceTests.swift
git commit -m "$(cat <<'EOF'
feat: add BonjourDiscoveryService for mDNS service discovery

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Device Discovery Coordinator

Create a coordinator that combines ARP and Bonjour discovery, manages device persistence.

**Files:**
- Create: `NetMonitor/Services/DeviceDiscoveryCoordinator.swift`
- Test: `NetMonitorTests/Services/DeviceDiscoveryCoordinatorTests.swift`

**Step 1: Write the failing test**

```swift
// NetMonitorTests/Services/DeviceDiscoveryCoordinatorTests.swift
import Testing
import SwiftData
@testable import NetMonitor

@Suite("DeviceDiscoveryCoordinator Tests")
struct DeviceDiscoveryCoordinatorTests {

    @Test("Coordinator initializes with not scanning state")
    @MainActor
    func initialState() {
        let container = try! ModelContainer(
            for: LocalDevice.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let coordinator = DeviceDiscoveryCoordinator(modelContext: container.mainContext)

        #expect(coordinator.isScanning == false)
        #expect(coordinator.discoveredDevices.isEmpty)
    }

    @Test("Merge discovery results updates existing device")
    @MainActor
    func mergeUpdatesExisting() async {
        let container = try! ModelContainer(
            for: LocalDevice.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        // Create existing device
        let existing = LocalDevice(
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: nil,
            vendor: nil,
            deviceType: .unknown
        )
        context.insert(existing)

        let coordinator = DeviceDiscoveryCoordinator(modelContext: context)

        // Simulate discovery with new hostname
        let discovered = DiscoveredDevice(
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "new-hostname.local"
        )

        await coordinator.mergeDiscoveredDevices([discovered])

        // Verify hostname was updated
        let devices = try! context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 1)
        #expect(devices.first?.hostname == "new-hostname.local")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor test -only-testing:NetMonitorTests/DeviceDiscoveryCoordinatorTests 2>&1 | head -50`
Expected: FAIL - DeviceDiscoveryCoordinator not defined

**Step 3: Write the DeviceDiscoveryCoordinator implementation**

```swift
// NetMonitor/Services/DeviceDiscoveryCoordinator.swift
import Foundation
import SwiftData

/// Coordinates device discovery from multiple sources and manages persistence
@MainActor
@Observable
final class DeviceDiscoveryCoordinator {

    private(set) var isScanning: Bool = false
    private(set) var discoveredDevices: [LocalDevice] = []
    private(set) var lastScanTime: Date?
    private(set) var scanProgress: Double = 0.0

    private let modelContext: ModelContext
    private let arpScanner: ARPScannerService
    private let bonjourScanner: BonjourDiscoveryService
    private let vendorLookup: MACVendorLookupService

    private var scanTask: Task<Void, Never>?

    init(
        modelContext: ModelContext,
        arpScanner: ARPScannerService = ARPScannerService(),
        bonjourScanner: BonjourDiscoveryService = BonjourDiscoveryService(),
        vendorLookup: MACVendorLookupService = MACVendorLookupService()
    ) {
        self.modelContext = modelContext
        self.arpScanner = arpScanner
        self.bonjourScanner = bonjourScanner
        self.vendorLookup = vendorLookup

        loadPersistedDevices()
    }

    /// Start a full network scan
    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0.0

        scanTask = Task {
            do {
                // Phase 1: ARP Scan (60% of progress)
                scanProgress = 0.1
                let arpDevices = try await arpScanner.scanNetwork()
                scanProgress = 0.6

                // Phase 2: Bonjour Discovery (30% of progress)
                let bonjourDevices = try await bonjourScanner.scanNetwork()
                scanProgress = 0.9

                // Merge results
                let allDiscovered = mergeDiscoveryResults(arp: arpDevices, bonjour: bonjourDevices)
                await mergeDiscoveredDevices(allDiscovered)

                // Phase 3: Vendor lookup (10% of progress)
                await lookupVendors()

                scanProgress = 1.0
                lastScanTime = Date()
            } catch {
                print("Scan error: \(error)")
            }

            isScanning = false
        }
    }

    /// Stop the current scan
    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        Task {
            await arpScanner.stopScan()
            await bonjourScanner.stopDiscovery()
        }
        isScanning = false
    }

    /// Merge discovered devices into persistent storage
    func mergeDiscoveredDevices(_ devices: [DiscoveredDevice]) async {
        for discovered in devices {
            // Find existing device by MAC address (primary) or IP (fallback)
            let predicate: Predicate<LocalDevice>
            if !discovered.macAddress.isEmpty {
                predicate = #Predicate<LocalDevice> { device in
                    device.macAddress == discovered.macAddress
                }
            } else {
                predicate = #Predicate<LocalDevice> { device in
                    device.ipAddress == discovered.ipAddress
                }
            }

            let descriptor = FetchDescriptor<LocalDevice>(predicate: predicate)
            let existing = try? modelContext.fetch(descriptor).first

            if let existing = existing {
                // Update existing device
                existing.ipAddress = discovered.ipAddress
                if let hostname = discovered.hostname, !hostname.isEmpty {
                    existing.hostname = hostname
                }
                existing.lastSeen = Date()
                existing.isOnline = true
            } else {
                // Create new device
                let newDevice = LocalDevice(
                    ipAddress: discovered.ipAddress,
                    macAddress: discovered.macAddress,
                    hostname: discovered.hostname,
                    vendor: nil,
                    deviceType: .unknown
                )
                modelContext.insert(newDevice)
            }
        }

        try? modelContext.save()
        loadPersistedDevices()
    }

    /// Mark devices not seen in current scan as offline
    func markOfflineDevices(currentIPs: Set<String>) {
        for device in discoveredDevices {
            if !currentIPs.contains(device.ipAddress) {
                device.isOnline = false
            }
        }
        try? modelContext.save()
    }

    // MARK: - Private Methods

    private func loadPersistedDevices() {
        let descriptor = FetchDescriptor<LocalDevice>(
            sortBy: [SortDescriptor(\.lastSeen, order: .reverse)]
        )
        discoveredDevices = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func mergeDiscoveryResults(
        arp: [DiscoveredDevice],
        bonjour: [DiscoveredDevice]
    ) -> [DiscoveredDevice] {
        var merged: [String: DiscoveredDevice] = [:]

        // ARP devices are authoritative for MAC addresses
        for device in arp {
            let key = device.ipAddress
            merged[key] = device
        }

        // Bonjour devices may have hostnames
        for device in bonjour {
            let key = device.ipAddress
            if var existing = merged[key] {
                // Merge hostname from Bonjour if we don't have one
                if existing.hostname == nil && device.hostname != nil {
                    merged[key] = DiscoveredDevice(
                        ipAddress: existing.ipAddress,
                        macAddress: existing.macAddress,
                        hostname: device.hostname
                    )
                }
            } else {
                merged[key] = device
            }
        }

        return Array(merged.values)
    }

    private func lookupVendors() async {
        for device in discoveredDevices {
            if device.vendor == nil && !device.macAddress.isEmpty {
                if let vendor = await vendorLookup.lookup(macAddress: device.macAddress) {
                    device.vendor = vendor
                }
            }
        }
        try? modelContext.save()
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor test -only-testing:NetMonitorTests/DeviceDiscoveryCoordinatorTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add NetMonitor/Services/DeviceDiscoveryCoordinator.swift NetMonitorTests/Services/DeviceDiscoveryCoordinatorTests.swift
git commit -m "$(cat <<'EOF'
feat: add DeviceDiscoveryCoordinator for unified device management

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: MAC Vendor Lookup Service

Implement MAC address vendor lookup using a bundled OUI database.

**Files:**
- Create: `NetMonitor/Services/MACVendorLookupService.swift`
- Create: `NetMonitor/Resources/oui.txt` (partial OUI database)
- Test: `NetMonitorTests/Services/MACVendorLookupServiceTests.swift`

**Step 1: Write the failing test**

```swift
// NetMonitorTests/Services/MACVendorLookupServiceTests.swift
import Testing
@testable import NetMonitor

@Suite("MACVendorLookupService Tests")
struct MACVendorLookupServiceTests {

    @Test("Lookup returns vendor for known MAC prefix")
    func knownVendor() async {
        let service = MACVendorLookupService()

        // Apple MAC prefix
        let vendor = await service.lookup(macAddress: "00:1A:2B:00:00:00")
        #expect(vendor != nil)
    }

    @Test("Lookup handles different MAC formats")
    func macFormats() async {
        let service = MACVendorLookupService()

        // Should handle colons, dashes, or no separators
        let v1 = await service.lookup(macAddress: "001A2B000000")
        let v2 = await service.lookup(macAddress: "00-1A-2B-00-00-00")
        let v3 = await service.lookup(macAddress: "00:1A:2B:00:00:00")

        #expect(v1 == v2)
        #expect(v2 == v3)
    }

    @Test("Lookup returns nil for unknown MAC")
    func unknownVendor() async {
        let service = MACVendorLookupService()

        let vendor = await service.lookup(macAddress: "FF:FF:FF:FF:FF:FF")
        #expect(vendor == nil)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor test -only-testing:NetMonitorTests/MACVendorLookupServiceTests 2>&1 | head -50`
Expected: FAIL - MACVendorLookupService not defined

**Step 3: Write the MACVendorLookupService implementation**

```swift
// NetMonitor/Services/MACVendorLookupService.swift
import Foundation

/// Service for looking up MAC address vendors from OUI database
actor MACVendorLookupService {

    /// Common vendor prefixes (OUI - first 3 bytes of MAC address)
    private let vendorDatabase: [String: String] = [
        // Apple
        "00:1A:2B": "Ayecom Technology",
        "00:03:93": "Apple",
        "00:05:02": "Apple",
        "00:0A:27": "Apple",
        "00:0A:95": "Apple",
        "00:0D:93": "Apple",
        "00:10:FA": "Apple",
        "00:11:24": "Apple",
        "00:14:51": "Apple",
        "00:16:CB": "Apple",
        "00:17:F2": "Apple",
        "00:19:E3": "Apple",
        "00:1B:63": "Apple",
        "00:1C:B3": "Apple",
        "00:1D:4F": "Apple",
        "00:1E:52": "Apple",
        "00:1E:C2": "Apple",
        "00:1F:5B": "Apple",
        "00:1F:F3": "Apple",
        "00:21:E9": "Apple",
        "00:22:41": "Apple",
        "00:23:12": "Apple",
        "00:23:32": "Apple",
        "00:23:6C": "Apple",
        "00:23:DF": "Apple",
        "00:24:36": "Apple",
        "00:25:00": "Apple",
        "00:25:4B": "Apple",
        "00:25:BC": "Apple",
        "00:26:08": "Apple",
        "00:26:4A": "Apple",
        "00:26:B0": "Apple",
        "00:26:BB": "Apple",
        "00:30:65": "Apple",
        "00:3E:E1": "Apple",
        "00:50:E4": "Apple",
        "00:56:CD": "Apple",
        "00:61:71": "Apple",
        "00:6D:52": "Apple",
        "00:88:65": "Apple",
        "00:B3:62": "Apple",
        "00:C6:10": "Apple",
        "00:CD:FE": "Apple",
        "00:DB:70": "Apple",
        "00:F4:B9": "Apple",
        "00:F7:6F": "Apple",

        // Samsung
        "00:00:F0": "Samsung",
        "00:02:78": "Samsung",
        "00:07:AB": "Samsung",
        "00:09:18": "Samsung",
        "00:0D:AE": "Samsung",
        "00:12:47": "Samsung",
        "00:12:FB": "Samsung",
        "00:13:77": "Samsung",
        "00:15:99": "Samsung",
        "00:15:B9": "Samsung",
        "00:16:32": "Samsung",
        "00:16:6B": "Samsung",
        "00:16:6C": "Samsung",
        "00:16:DB": "Samsung",
        "00:17:C9": "Samsung",
        "00:17:D5": "Samsung",
        "00:18:AF": "Samsung",

        // Google
        "00:1A:11": "Google",
        "3C:5A:B4": "Google",
        "54:60:09": "Google",
        "94:EB:2C": "Google",
        "F4:F5:D8": "Google",
        "F4:F5:E8": "Google",

        // Amazon
        "00:FC:8B": "Amazon",
        "0C:47:C9": "Amazon",
        "10:CE:A9": "Amazon",
        "14:91:82": "Amazon",
        "18:74:2E": "Amazon",
        "34:D2:70": "Amazon",
        "38:F7:3D": "Amazon",
        "40:B4:CD": "Amazon",
        "44:65:0D": "Amazon",
        "4C:EF:C0": "Amazon",
        "50:DC:E7": "Amazon",
        "50:F5:DA": "Amazon",
        "68:37:E9": "Amazon",
        "68:54:FD": "Amazon",

        // Microsoft
        "00:03:FF": "Microsoft",
        "00:0D:3A": "Microsoft",
        "00:12:5A": "Microsoft",
        "00:15:5D": "Microsoft",
        "00:17:FA": "Microsoft",
        "00:1D:D8": "Microsoft",
        "00:22:48": "Microsoft",
        "00:25:AE": "Microsoft",
        "00:50:F2": "Microsoft",
        "28:18:78": "Microsoft",
        "30:59:B7": "Microsoft",

        // Intel
        "00:02:B3": "Intel",
        "00:03:47": "Intel",
        "00:04:23": "Intel",
        "00:07:E9": "Intel",
        "00:0C:F1": "Intel",
        "00:0E:0C": "Intel",
        "00:0E:35": "Intel",
        "00:11:11": "Intel",
        "00:12:F0": "Intel",
        "00:13:02": "Intel",
        "00:13:20": "Intel",
        "00:13:CE": "Intel",
        "00:13:E8": "Intel",

        // TP-Link
        "00:27:19": "TP-Link",
        "10:FE:ED": "TP-Link",
        "14:CC:20": "TP-Link",
        "14:CF:92": "TP-Link",
        "18:A6:F7": "TP-Link",
        "1C:3B:F3": "TP-Link",
        "30:B5:C2": "TP-Link",
        "50:C7:BF": "TP-Link",
        "54:C8:0F": "TP-Link",

        // Netgear
        "00:09:5B": "Netgear",
        "00:0F:B5": "Netgear",
        "00:14:6C": "Netgear",
        "00:18:4D": "Netgear",
        "00:1B:2F": "Netgear",
        "00:1E:2A": "Netgear",
        "00:1F:33": "Netgear",
        "00:22:3F": "Netgear",
        "00:24:B2": "Netgear",
        "00:26:F2": "Netgear",

        // Cisco
        "00:00:0C": "Cisco",
        "00:01:42": "Cisco",
        "00:01:43": "Cisco",
        "00:01:63": "Cisco",
        "00:01:64": "Cisco",
        "00:01:96": "Cisco",
        "00:01:97": "Cisco",
        "00:01:C7": "Cisco",
        "00:01:C9": "Cisco",
        "00:02:16": "Cisco",
        "00:02:17": "Cisco",
        "00:02:3D": "Cisco",

        // Raspberry Pi
        "28:CD:C1": "Raspberry Pi",
        "B8:27:EB": "Raspberry Pi",
        "DC:A6:32": "Raspberry Pi",
        "E4:5F:01": "Raspberry Pi",

        // Sonos
        "00:0E:58": "Sonos",
        "34:7E:5C": "Sonos",
        "48:A6:B8": "Sonos",
        "54:2A:1B": "Sonos",
        "5C:AA:FD": "Sonos",
        "78:28:CA": "Sonos",
        "94:9F:3E": "Sonos",
        "B8:E9:37": "Sonos"
    ]

    /// Look up the vendor for a MAC address
    /// - Parameter macAddress: MAC address in any format (colons, dashes, or none)
    /// - Returns: Vendor name if found
    func lookup(macAddress: String) -> String? {
        let normalized = normalizeMAC(macAddress)
        let prefix = String(normalized.prefix(8)) // First 3 bytes = OUI
        return vendorDatabase[prefix]
    }

    /// Normalize MAC address to XX:XX:XX:XX:XX:XX format
    private func normalizeMAC(_ mac: String) -> String {
        // Remove separators and convert to uppercase
        let cleaned = mac
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()

        guard cleaned.count >= 6 else { return "" }

        // Insert colons every 2 characters
        var result = ""
        for (index, char) in cleaned.enumerated() {
            if index > 0 && index % 2 == 0 && index < 12 {
                result += ":"
            }
            result.append(char)
        }

        return result
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor test -only-testing:NetMonitorTests/MACVendorLookupServiceTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add NetMonitor/Services/MACVendorLookupService.swift NetMonitorTests/Services/MACVendorLookupServiceTests.swift
git commit -m "$(cat <<'EOF'
feat: add MACVendorLookupService with common OUI prefixes

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Devices View Implementation

Build the DevicesView with device list, scan controls, and grid layout.

**Files:**
- Modify: `NetMonitor/Views/DevicesView.swift`
- Create: `NetMonitor/Views/DeviceRowView.swift`

**Step 1: Read existing DevicesView**

Read the current placeholder implementation to understand the starting point.

**Step 2: Write the DeviceRowView component**

```swift
// NetMonitor/Views/DeviceRowView.swift
import SwiftUI

struct DeviceRowView: View {
    let device: LocalDevice

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(device.isOnline ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            // Device icon
            Image(systemName: device.deviceType.iconName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            // Device info
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.headline)

                Text(device.ipAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontDesign(.monospaced)
            }

            Spacer()

            // Vendor badge
            if let vendor = device.vendor {
                Text(vendor)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }

            // MAC address
            if !device.macAddress.isEmpty {
                Text(device.macAddress)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fontDesign(.monospaced)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - LocalDevice Extension

extension LocalDevice {
    var displayName: String {
        customName ?? hostname ?? ipAddress
    }
}

// MARK: - Preview

#Preview {
    List {
        DeviceRowView(device: LocalDevice(
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "macbook-pro.local",
            vendor: "Apple",
            deviceType: .laptop
        ))

        DeviceRowView(device: LocalDevice(
            ipAddress: "192.168.1.1",
            macAddress: "00:11:22:33:44:55",
            hostname: nil,
            vendor: "Netgear",
            deviceType: .router
        ))
    }
}
```

**Step 3: Update DevicesView with full implementation**

```swift
// NetMonitor/Views/DevicesView.swift
import SwiftUI
import SwiftData

struct DevicesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalDevice.lastSeen, order: .reverse) private var devices: [LocalDevice]

    @State private var coordinator: DeviceDiscoveryCoordinator?
    @State private var selectedDevice: LocalDevice?
    @State private var searchText: String = ""
    @State private var filterOnlineOnly: Bool = false

    var filteredDevices: [LocalDevice] {
        var result = devices

        if filterOnlineOnly {
            result = result.filter { $0.isOnline }
        }

        if !searchText.isEmpty {
            result = result.filter { device in
                device.displayName.localizedCaseInsensitiveContains(searchText) ||
                device.ipAddress.contains(searchText) ||
                device.macAddress.localizedCaseInsensitiveContains(searchText) ||
                (device.vendor?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return result
    }

    var body: some View {
        NavigationSplitView {
            deviceList
        } detail: {
            if let device = selectedDevice {
                DeviceDetailView(device: device)
            } else {
                ContentUnavailableView(
                    "Select a Device",
                    systemImage: "desktopcomputer",
                    description: Text("Choose a device from the list to view details")
                )
            }
        }
        .navigationTitle("Devices")
        .toolbar {
            toolbarContent
        }
        .searchable(text: $searchText, prompt: "Search devices...")
        .onAppear {
            if coordinator == nil {
                coordinator = DeviceDiscoveryCoordinator(modelContext: modelContext)
            }
        }
    }

    // MARK: - Device List

    private var deviceList: some View {
        Group {
            if devices.isEmpty && coordinator?.isScanning != true {
                ContentUnavailableView(
                    "No Devices Found",
                    systemImage: "network",
                    description: Text("Tap Scan to discover devices on your network")
                )
            } else {
                List(filteredDevices, selection: $selectedDevice) { device in
                    DeviceRowView(device: device)
                        .tag(device)
                        .contextMenu {
                            deviceContextMenu(for: device)
                        }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 300)
        .overlay {
            if coordinator?.isScanning == true {
                scanningOverlay
            }
        }
    }

    // MARK: - Scanning Overlay

    private var scanningOverlay: some View {
        VStack(spacing: 16) {
            ProgressView(value: coordinator?.scanProgress ?? 0)
                .progressViewStyle(.linear)
                .frame(width: 200)

            Text("Scanning network...")
                .font(.headline)

            Text("\(Int((coordinator?.scanProgress ?? 0) * 100))% complete")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Stop") {
                coordinator?.stopScan()
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                coordinator?.startScan()
            } label: {
                Label("Scan", systemImage: "antenna.radiowaves.left.and.right")
            }
            .disabled(coordinator?.isScanning == true)
        }

        ToolbarItem(placement: .automatic) {
            Toggle(isOn: $filterOnlineOnly) {
                Label("Online Only", systemImage: "circle.fill")
            }
            .toggleStyle(.button)
        }

        ToolbarItem(placement: .status) {
            HStack(spacing: 4) {
                Text("\(filteredDevices.count)")
                    .fontWeight(.semibold)
                Text("devices")
                    .foregroundStyle(.secondary)

                if let lastScan = coordinator?.lastScanTime {
                    Text("• Last scan: \(lastScan, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func deviceContextMenu(for device: LocalDevice) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(device.ipAddress, forType: .string)
        } label: {
            Label("Copy IP Address", systemImage: "doc.on.doc")
        }

        if !device.macAddress.isEmpty {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(device.macAddress, forType: .string)
            } label: {
                Label("Copy MAC Address", systemImage: "doc.on.doc")
            }
        }

        Divider()

        Button {
            // TODO: Implement ping
        } label: {
            Label("Ping Device", systemImage: "waveform.path")
        }

        Button {
            // TODO: Implement port scan
        } label: {
            Label("Scan Ports", systemImage: "network")
        }

        if !device.macAddress.isEmpty {
            Button {
                // TODO: Implement WOL
            } label: {
                Label("Wake on LAN", systemImage: "power")
            }
        }

        Divider()

        Button(role: .destructive) {
            modelContext.delete(device)
        } label: {
            Label("Remove Device", systemImage: "trash")
        }
    }
}

// MARK: - Preview

#Preview {
    DevicesView()
        .modelContainer(PreviewContainer.shared.container)
}
```

**Step 4: Build and verify no errors**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add NetMonitor/Views/DevicesView.swift NetMonitor/Views/DeviceRowView.swift
git commit -m "$(cat <<'EOF'
feat: implement DevicesView with discovery integration

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Device Detail View

Create a detail view for individual devices with actions and editing.

**Files:**
- Create: `NetMonitor/Views/DeviceDetailView.swift`

**Step 1: Write the DeviceDetailView**

```swift
// NetMonitor/Views/DeviceDetailView.swift
import SwiftUI
import SwiftData

struct DeviceDetailView: View {
    @Bindable var device: LocalDevice
    @Environment(\.modelContext) private var modelContext

    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var editedNotes: String = ""
    @State private var selectedDeviceType: DeviceType = .unknown

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header card
                headerCard

                // Network info card
                networkInfoCard

                // Timestamps card
                timestampsCard

                // Notes card
                notesCard

                // Actions
                actionsSection
            }
            .padding()
        }
        .navigationTitle(device.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        saveChanges()
                    } else {
                        startEditing()
                    }
                    isEditing.toggle()
                }
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: 16) {
            // Device icon
            ZStack {
                Circle()
                    .fill(device.isOnline ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 64, height: 64)

                Image(systemName: device.deviceType.iconName)
                    .font(.title)
                    .foregroundStyle(device.isOnline ? .green : .gray)
            }

            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField("Device Name", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(device.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(device.isOnline ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)

                    Text(device.isOnline ? "Online" : "Offline")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let vendor = device.vendor {
                    Text(vendor)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isEditing {
                Picker("Device Type", selection: $selectedDeviceType) {
                    ForEach(DeviceType.allCases, id: \.self) { type in
                        Label(type.rawValue.capitalized, systemImage: type.iconName)
                            .tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Network Info Card

    private var networkInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Network Information", systemImage: "network")
                .font(.headline)

            Divider()

            infoRow(label: "IP Address", value: device.ipAddress, monospace: true)

            if !device.macAddress.isEmpty {
                infoRow(label: "MAC Address", value: device.macAddress, monospace: true)
            }

            if let hostname = device.hostname {
                infoRow(label: "Hostname", value: hostname, monospace: true)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Timestamps Card

    private var timestampsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Activity", systemImage: "clock")
                .font(.headline)

            Divider()

            infoRow(
                label: "First Seen",
                value: device.firstSeen.formatted(date: .abbreviated, time: .shortened)
            )

            infoRow(
                label: "Last Seen",
                value: device.lastSeen.formatted(date: .abbreviated, time: .shortened)
            )
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Notes Card

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)

            Divider()

            if isEditing {
                TextEditor(text: $editedNotes)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                if let notes = device.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No notes")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Actions", systemImage: "bolt")
                .font(.headline)

            Divider()

            HStack(spacing: 12) {
                actionButton(
                    title: "Ping",
                    systemImage: "waveform.path",
                    action: { /* TODO */ }
                )

                actionButton(
                    title: "Port Scan",
                    systemImage: "network",
                    action: { /* TODO */ }
                )

                if !device.macAddress.isEmpty {
                    actionButton(
                        title: "Wake",
                        systemImage: "power",
                        action: { /* TODO */ }
                    )
                }

                actionButton(
                    title: "Add to Targets",
                    systemImage: "plus.circle",
                    action: { addToTargets() }
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helper Views

    private func infoRow(label: String, value: String, monospace: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontDesign(monospace ? .monospaced : .default)
                .textSelection(.enabled)
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Actions

    private func startEditing() {
        editedName = device.customName ?? ""
        editedNotes = device.notes ?? ""
        selectedDeviceType = device.deviceType
    }

    private func saveChanges() {
        device.customName = editedName.isEmpty ? nil : editedName
        device.notes = editedNotes.isEmpty ? nil : editedNotes
        device.deviceType = selectedDeviceType
        try? modelContext.save()
    }

    private func addToTargets() {
        let target = NetworkTarget(
            name: device.displayName,
            host: device.ipAddress,
            port: nil,
            targetProtocol: .icmp,
            checkInterval: 30,
            timeout: 10,
            isEnabled: true
        )
        modelContext.insert(target)
        try? modelContext.save()
    }
}

// MARK: - DeviceType Extension

extension DeviceType: CaseIterable {
    public static var allCases: [DeviceType] {
        [.phone, .laptop, .tablet, .tv, .speaker, .gaming, .iot, .router, .printer, .unknown]
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DeviceDetailView(device: LocalDevice(
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "macbook-pro.local",
            vendor: "Apple",
            deviceType: .laptop
        ))
    }
    .modelContainer(PreviewContainer.shared.container)
}
```

**Step 2: Build and verify no errors**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add NetMonitor/Views/DeviceDetailView.swift
git commit -m "$(cat <<'EOF'
feat: add DeviceDetailView with editing and actions

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Menu Bar App Structure

Set up the menu bar extra with AppKit integration.

**Files:**
- Create: `NetMonitor/MenuBar/MenuBarController.swift`
- Modify: `NetMonitor/NetMonitorApp.swift`

**Step 1: Create the MenuBarController**

```swift
// NetMonitor/MenuBar/MenuBarController.swift
import SwiftUI
import AppKit

/// Controls the menu bar status item and popover
@MainActor
final class MenuBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    @Published var isVisible: Bool = false

    private let monitoringSession: MonitoringSession

    init(monitoringSession: MonitoringSession) {
        self.monitoringSession = monitoringSession
    }

    func setup() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "NetMonitor")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 400)
        popover?.behavior = .transient
        popover?.animates = true

        // Set SwiftUI content
        let contentView = MenuBarPopoverView(
            session: monitoringSession,
            onClose: { [weak self] in self?.closePopover() }
        )
        popover?.contentViewController = NSHostingController(rootView: contentView)
    }

    func teardown() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        popover = nil
    }

    @objc private func togglePopover() {
        if let popover = popover, let button = statusItem?.button {
            if popover.isShown {
                closePopover()
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                isVisible = true
            }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        isVisible = false
    }

    /// Update the status item icon based on monitoring state
    func updateIcon(isMonitoring: Bool, hasIssues: Bool) {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        if !isMonitoring {
            symbolName = "network.slash"
        } else if hasIssues {
            symbolName = "exclamationmark.triangle"
        } else {
            symbolName = "network"
        }

        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "NetMonitor")

        // Color the icon
        if hasIssues {
            button.contentTintColor = .systemRed
        } else if isMonitoring {
            button.contentTintColor = .systemGreen
        } else {
            button.contentTintColor = nil
        }
    }
}
```

**Step 2: Update NetMonitorApp to include menu bar**

```swift
// NetMonitor/NetMonitorApp.swift
import SwiftUI
import SwiftData

@main
struct NetMonitorApp: App {
    @State private var monitoringSession: MonitoringSession?
    @State private var menuBarController: MenuBarController?

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            NetworkTarget.self,
            TargetMeasurement.self,
            LocalDevice.self,
            SessionRecord.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(monitoringSession)
                .onAppear {
                    setupMonitoringSession()
                    setupMenuBar()
                }
        }
        .modelContainer(sharedModelContainer)

        Settings {
            SettingsView()
        }
    }

    private func setupMonitoringSession() {
        if monitoringSession == nil {
            monitoringSession = MonitoringSession(
                modelContainer: sharedModelContainer
            )
        }
    }

    private func setupMenuBar() {
        guard let session = monitoringSession, menuBarController == nil else { return }
        menuBarController = MenuBarController(monitoringSession: session)
        menuBarController?.setup()
    }
}
```

**Step 3: Build and verify no errors**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add NetMonitor/MenuBar/MenuBarController.swift NetMonitor/NetMonitorApp.swift
git commit -m "$(cat <<'EOF'
feat: add MenuBarController for status item management

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Menu Bar Status View

Create the popover content view for the menu bar.

**Files:**
- Create: `NetMonitor/MenuBar/MenuBarPopoverView.swift`

**Step 1: Write the MenuBarPopoverView**

```swift
// NetMonitor/MenuBar/MenuBarPopoverView.swift
import SwiftUI

struct MenuBarPopoverView: View {
    @Bindable var session: MonitoringSession
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Quick stats
            quickStats

            Divider()

            // Target status list
            targetList

            Divider()

            // Footer actions
            footer
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("NetMonitor")
                    .font(.headline)

                HStack(spacing: 4) {
                    Circle()
                        .fill(session.isMonitoring ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)

                    Text(session.isMonitoring ? "Monitoring" : "Stopped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Start/Stop button
            Button {
                if session.isMonitoring {
                    session.stopMonitoring()
                } else {
                    Task {
                        await session.startMonitoring()
                    }
                }
            } label: {
                Image(systemName: session.isMonitoring ? "stop.fill" : "play.fill")
                    .foregroundStyle(session.isMonitoring ? .red : .green)
            }
            .buttonStyle(.borderless)
            .help(session.isMonitoring ? "Stop Monitoring" : "Start Monitoring")
        }
        .padding()
    }

    // MARK: - Quick Stats

    private var quickStats: some View {
        HStack(spacing: 16) {
            statItem(
                value: "\(onlineTargetCount)",
                label: "Online",
                color: .green
            )

            statItem(
                value: "\(offlineTargetCount)",
                label: "Offline",
                color: .red
            )

            statItem(
                value: averageLatencyString,
                label: "Avg Latency",
                color: .blue
            )
        }
        .padding()
    }

    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(color)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Target List

    private var targetList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(session.latestResults.keys.prefix(5)), id: \.self) { targetID in
                    if let measurement = session.latestResults[targetID] {
                        targetRow(targetID: targetID, measurement: measurement)
                    }
                }

                if session.latestResults.isEmpty {
                    Text("No targets configured")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding()
                }
            }
            .padding(.horizontal)
        }
        .frame(maxHeight: 200)
    }

    private func targetRow(targetID: UUID, measurement: TargetMeasurement) -> some View {
        HStack {
            Circle()
                .fill(measurement.isReachable ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(targetID.uuidString.prefix(8))
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if measurement.isReachable, let latency = measurement.latency {
                Text("\(Int(latency))ms")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
            } else {
                Text("Offline")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Open NetMonitor") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title.contains("NetMonitor") || $0.isMainWindow }) {
                    window.makeKeyAndOrderFront(nil)
                }
                onClose()
            }
            .buttonStyle(.borderless)

            Spacer()

            if let startTime = session.startTime {
                Text("Running: \(startTime, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    // MARK: - Computed Properties

    private var onlineTargetCount: Int {
        session.latestResults.values.filter { $0.isReachable }.count
    }

    private var offlineTargetCount: Int {
        session.latestResults.values.filter { !$0.isReachable }.count
    }

    private var averageLatencyString: String {
        let latencies = session.latestResults.values.compactMap { $0.latency }
        guard !latencies.isEmpty else { return "—" }
        let avg = latencies.reduce(0, +) / Double(latencies.count)
        return "\(Int(avg))ms"
    }
}

// MARK: - Preview

#Preview {
    MenuBarPopoverView(
        session: MonitoringSession(
            modelContainer: try! ModelContainer(
                for: NetworkTarget.self, TargetMeasurement.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        ),
        onClose: {}
    )
}
```

**Step 2: Build and verify no errors**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add NetMonitor/MenuBar/MenuBarPopoverView.swift
git commit -m "$(cat <<'EOF'
feat: add MenuBarPopoverView with quick stats and target list

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Menu Bar Quick Actions

Add keyboard shortcuts and notification center integration.

**Files:**
- Modify: `NetMonitor/MenuBar/MenuBarController.swift`
- Create: `NetMonitor/MenuBar/MenuBarCommands.swift`

**Step 1: Create MenuBarCommands for keyboard shortcuts**

```swift
// NetMonitor/MenuBar/MenuBarCommands.swift
import SwiftUI

struct MenuBarCommands: Commands {
    @Binding var isMonitoring: Bool
    let startMonitoring: () async -> Void
    let stopMonitoring: () -> Void

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(isMonitoring ? "Stop Monitoring" : "Start Monitoring") {
                if isMonitoring {
                    stopMonitoring()
                } else {
                    Task {
                        await startMonitoring()
                    }
                }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Divider()
        }

        CommandGroup(replacing: .newItem) {
            Button("Scan Network") {
                // Post notification to trigger scan
                NotificationCenter.default.post(
                    name: .scanNetworkRequested,
                    object: nil
                )
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let scanNetworkRequested = Notification.Name("scanNetworkRequested")
    static let monitoringStateChanged = Notification.Name("monitoringStateChanged")
    static let targetStatusChanged = Notification.Name("targetStatusChanged")
}
```

**Step 2: Update NetMonitorApp to include commands**

Add to NetMonitorApp.swift after the Settings scene:

```swift
// Add this method to NetMonitorApp
@CommandsBuilder
private var appCommands: some Commands {
    if let session = monitoringSession {
        MenuBarCommands(
            isMonitoring: .init(
                get: { session.isMonitoring },
                set: { _ in }
            ),
            startMonitoring: { await session.startMonitoring() },
            stopMonitoring: { session.stopMonitoring() }
        )
    }
}
```

**Step 3: Build and verify no errors**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add NetMonitor/MenuBar/MenuBarCommands.swift NetMonitor/NetMonitorApp.swift
git commit -m "$(cat <<'EOF'
feat: add keyboard shortcuts for monitoring control

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Companion Protocol Definition

Define the JSON message protocol for companion app communication.

**Files:**
- Create: `NetMonitorShared/Sources/NetMonitorShared/Protocol/CompanionMessage.swift`
- Test: `NetMonitorTests/Protocol/CompanionMessageTests.swift`

**Step 1: Write the failing test**

```swift
// NetMonitorTests/Protocol/CompanionMessageTests.swift
import Testing
@testable import NetMonitorShared

@Suite("CompanionMessage Protocol Tests")
struct CompanionMessageTests {

    @Test("Encode status update message")
    func encodeStatusUpdate() throws {
        let message = CompanionMessage.statusUpdate(StatusUpdatePayload(
            isMonitoring: true,
            onlineTargets: 5,
            offlineTargets: 2,
            averageLatency: 45.5
        ))

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(CompanionMessage.self, from: data)

        if case .statusUpdate(let payload) = decoded {
            #expect(payload.isMonitoring == true)
            #expect(payload.onlineTargets == 5)
            #expect(payload.offlineTargets == 2)
            #expect(payload.averageLatency == 45.5)
        } else {
            Issue.record("Expected statusUpdate message type")
        }
    }

    @Test("Encode command message")
    func encodeCommand() throws {
        let message = CompanionMessage.command(CommandPayload(
            action: .startMonitoring,
            parameters: nil
        ))

        let data = try JSONEncoder().encode(message)
        let json = String(data: data, encoding: .utf8)

        #expect(json?.contains("startMonitoring") == true)
    }

    @Test("Decode device list message")
    func decodeDeviceList() throws {
        let json = """
        {
            "type": "deviceList",
            "payload": {
                "devices": [
                    {
                        "ipAddress": "192.168.1.100",
                        "macAddress": "AA:BB:CC:DD:EE:FF",
                        "hostname": "test.local",
                        "isOnline": true
                    }
                ]
            }
        }
        """

        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(CompanionMessage.self, from: data)

        if case .deviceList(let payload) = message {
            #expect(payload.devices.count == 1)
            #expect(payload.devices[0].ipAddress == "192.168.1.100")
        } else {
            Issue.record("Expected deviceList message type")
        }
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor test -only-testing:NetMonitorTests/CompanionMessageTests 2>&1 | head -50`
Expected: FAIL - CompanionMessage not defined

**Step 3: Write the CompanionMessage protocol types**

```swift
// NetMonitorShared/Sources/NetMonitorShared/Protocol/CompanionMessage.swift
import Foundation

// MARK: - Message Types

/// Root message type for companion app communication
public enum CompanionMessage: Codable, Sendable {
    case statusUpdate(StatusUpdatePayload)
    case targetList(TargetListPayload)
    case deviceList(DeviceListPayload)
    case command(CommandPayload)
    case toolResult(ToolResultPayload)
    case error(ErrorPayload)
    case heartbeat(HeartbeatPayload)

    enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "statusUpdate":
            let payload = try container.decode(StatusUpdatePayload.self, forKey: .payload)
            self = .statusUpdate(payload)
        case "targetList":
            let payload = try container.decode(TargetListPayload.self, forKey: .payload)
            self = .targetList(payload)
        case "deviceList":
            let payload = try container.decode(DeviceListPayload.self, forKey: .payload)
            self = .deviceList(payload)
        case "command":
            let payload = try container.decode(CommandPayload.self, forKey: .payload)
            self = .command(payload)
        case "toolResult":
            let payload = try container.decode(ToolResultPayload.self, forKey: .payload)
            self = .toolResult(payload)
        case "error":
            let payload = try container.decode(ErrorPayload.self, forKey: .payload)
            self = .error(payload)
        case "heartbeat":
            let payload = try container.decode(HeartbeatPayload.self, forKey: .payload)
            self = .heartbeat(payload)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown message type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .statusUpdate(let payload):
            try container.encode("statusUpdate", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .targetList(let payload):
            try container.encode("targetList", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .deviceList(let payload):
            try container.encode("deviceList", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .command(let payload):
            try container.encode("command", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .toolResult(let payload):
            try container.encode("toolResult", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .error(let payload):
            try container.encode("error", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .heartbeat(let payload):
            try container.encode("heartbeat", forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}

// MARK: - Payload Types

public struct StatusUpdatePayload: Codable, Sendable {
    public let isMonitoring: Bool
    public let onlineTargets: Int
    public let offlineTargets: Int
    public let averageLatency: Double?
    public let timestamp: Date

    public init(
        isMonitoring: Bool,
        onlineTargets: Int,
        offlineTargets: Int,
        averageLatency: Double?,
        timestamp: Date = Date()
    ) {
        self.isMonitoring = isMonitoring
        self.onlineTargets = onlineTargets
        self.offlineTargets = offlineTargets
        self.averageLatency = averageLatency
        self.timestamp = timestamp
    }
}

public struct TargetListPayload: Codable, Sendable {
    public let targets: [TargetInfo]

    public init(targets: [TargetInfo]) {
        self.targets = targets
    }
}

public struct TargetInfo: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let host: String
    public let port: Int?
    public let `protocol`: String
    public let isEnabled: Bool
    public let isReachable: Bool?
    public let latency: Double?

    public init(
        id: UUID,
        name: String,
        host: String,
        port: Int?,
        protocol: String,
        isEnabled: Bool,
        isReachable: Bool?,
        latency: Double?
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.protocol = `protocol`
        self.isEnabled = isEnabled
        self.isReachable = isReachable
        self.latency = latency
    }
}

public struct DeviceListPayload: Codable, Sendable {
    public let devices: [DeviceInfo]

    public init(devices: [DeviceInfo]) {
        self.devices = devices
    }
}

public struct DeviceInfo: Codable, Sendable, Identifiable {
    public let id: UUID
    public let ipAddress: String
    public let macAddress: String
    public let hostname: String?
    public let vendor: String?
    public let deviceType: String
    public let isOnline: Bool

    public init(
        id: UUID = UUID(),
        ipAddress: String,
        macAddress: String,
        hostname: String?,
        vendor: String? = nil,
        deviceType: String = "unknown",
        isOnline: Bool
    ) {
        self.id = id
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.hostname = hostname
        self.vendor = vendor
        self.deviceType = deviceType
        self.isOnline = isOnline
    }
}

public struct CommandPayload: Codable, Sendable {
    public let action: CommandAction
    public let parameters: [String: String]?

    public init(action: CommandAction, parameters: [String: String]?) {
        self.action = action
        self.parameters = parameters
    }
}

public enum CommandAction: String, Codable, Sendable {
    case startMonitoring
    case stopMonitoring
    case scanDevices
    case ping
    case traceroute
    case portScan
    case dnsLookup
    case wakeOnLan
    case refreshTargets
    case refreshDevices
}

public struct ToolResultPayload: Codable, Sendable {
    public let tool: String
    public let success: Bool
    public let result: String
    public let timestamp: Date

    public init(tool: String, success: Bool, result: String, timestamp: Date = Date()) {
        self.tool = tool
        self.success = success
        self.result = result
        self.timestamp = timestamp
    }
}

public struct ErrorPayload: Codable, Sendable {
    public let code: String
    public let message: String
    public let timestamp: Date

    public init(code: String, message: String, timestamp: Date = Date()) {
        self.code = code
        self.message = message
        self.timestamp = timestamp
    }
}

public struct HeartbeatPayload: Codable, Sendable {
    public let timestamp: Date
    public let version: String

    public init(timestamp: Date = Date(), version: String = "1.0") {
        self.timestamp = timestamp
        self.version = version
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor test -only-testing:NetMonitorTests/CompanionMessageTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add NetMonitorShared/Sources/NetMonitorShared/Protocol/CompanionMessage.swift NetMonitorTests/Protocol/CompanionMessageTests.swift
git commit -m "$(cat <<'EOF'
feat: add CompanionMessage JSON protocol types

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Companion Service Server

Implement the Bonjour service that listens for companion app connections.

**Files:**
- Create: `NetMonitor/Services/CompanionService.swift`
- Test: `NetMonitorTests/Services/CompanionServiceTests.swift`

**Step 1: Write the failing test**

```swift
// NetMonitorTests/Services/CompanionServiceTests.swift
import Testing
import Network
@testable import NetMonitor

@Suite("CompanionService Tests")
struct CompanionServiceTests {

    @Test("Service initializes with correct port")
    func servicePort() async {
        let service = CompanionService()
        let port = await service.port
        #expect(port == 8849)
    }

    @Test("Service starts in stopped state")
    func initialState() async {
        let service = CompanionService()
        let isRunning = await service.isRunning
        #expect(isRunning == false)
    }

    @Test("Service type matches spec")
    func serviceType() async {
        let service = CompanionService()
        let type = await service.serviceType
        #expect(type == "_netmon._tcp")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor test -only-testing:NetMonitorTests/CompanionServiceTests 2>&1 | head -50`
Expected: FAIL - CompanionService not defined

**Step 3: Write the CompanionService implementation**

```swift
// NetMonitor/Services/CompanionService.swift
import Foundation
import Network
import NetMonitorShared

/// Bonjour service for companion app communication
actor CompanionService {

    let port: UInt16 = 8849
    let serviceType = "_netmon._tcp"
    let serviceName = "NetMonitor"

    private(set) var isRunning = false
    private(set) var connectedClients: [UUID: NWConnection] = [:]

    private var listener: NWListener?
    private var messageHandler: ((CompanionMessage, UUID) async -> CompanionMessage?)?

    /// Start the Bonjour service
    func start(messageHandler: @escaping (CompanionMessage, UUID) async -> CompanionMessage?) throws {
        guard !isRunning else { return }

        self.messageHandler = messageHandler

        // Create listener
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        // Add Bonjour service advertisement
        let txtRecord = NWTXTRecord()
        parameters.defaultProtocolStack.applicationProtocols.insert(
            NWProtocolFramer.Options(definition: CompanionFramer.definition),
            at: 0
        )

        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

        listener?.service = NWListener.Service(
            name: serviceName,
            type: serviceType,
            domain: "local.",
            txtRecord: txtRecord
        )

        listener?.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleListenerState(state)
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { [weak self] in
                await self?.handleNewConnection(connection)
            }
        }

        listener?.start(queue: .global())
        isRunning = true
    }

    /// Stop the service
    func stop() {
        listener?.cancel()
        listener = nil

        for (_, connection) in connectedClients {
            connection.cancel()
        }
        connectedClients.removeAll()

        isRunning = false
    }

    /// Send a message to all connected clients
    func broadcast(_ message: CompanionMessage) async {
        guard let data = try? JSONEncoder().encode(message) else { return }

        for (id, connection) in connectedClients {
            await send(data: data, to: connection, clientID: id)
        }
    }

    /// Send a message to a specific client
    func send(_ message: CompanionMessage, to clientID: UUID) async {
        guard let connection = connectedClients[clientID],
              let data = try? JSONEncoder().encode(message) else { return }

        await send(data: data, to: connection, clientID: clientID)
    }

    // MARK: - Private Methods

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("CompanionService: Listening on port \(port)")
        case .failed(let error):
            print("CompanionService: Failed - \(error)")
            isRunning = false
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let clientID = UUID()
        connectedClients[clientID] = connection

        print("CompanionService: New connection from client \(clientID)")

        connection.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleConnectionState(state, clientID: clientID)
            }
        }

        connection.start(queue: .global())
        receiveMessage(from: connection, clientID: clientID)
    }

    private func handleConnectionState(_ state: NWConnection.State, clientID: UUID) {
        switch state {
        case .ready:
            print("CompanionService: Client \(clientID) connected")
            // Send initial status
            Task {
                await send(
                    .heartbeat(HeartbeatPayload()),
                    to: clientID
                )
            }
        case .failed(let error):
            print("CompanionService: Client \(clientID) failed - \(error)")
            connectedClients.removeValue(forKey: clientID)
        case .cancelled:
            print("CompanionService: Client \(clientID) disconnected")
            connectedClients.removeValue(forKey: clientID)
        default:
            break
        }
    }

    private nonisolated func receiveMessage(from connection: NWConnection, clientID: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                Task { [weak self] in
                    await self?.processReceivedData(data, clientID: clientID)
                }
            }

            if let error = error {
                print("CompanionService: Receive error - \(error)")
                return
            }

            if !isComplete {
                self?.receiveMessage(from: connection, clientID: clientID)
            }
        }
    }

    private func processReceivedData(_ data: Data, clientID: UUID) async {
        do {
            let message = try JSONDecoder().decode(CompanionMessage.self, from: data)
            print("CompanionService: Received \(message) from \(clientID)")

            // Handle message and get response
            if let response = await messageHandler?(message, clientID) {
                await send(response, to: clientID)
            }
        } catch {
            print("CompanionService: Failed to decode message - \(error)")
            await send(
                .error(ErrorPayload(
                    code: "DECODE_ERROR",
                    message: "Failed to decode message: \(error.localizedDescription)"
                )),
                to: clientID
            )
        }
    }

    private nonisolated func send(data: Data, to connection: NWConnection, clientID: UUID) async {
        // Prefix with length for framing
        var length = UInt32(data.count).bigEndian
        var framedData = Data(bytes: &length, count: 4)
        framedData.append(data)

        connection.send(content: framedData, completion: .contentProcessed { error in
            if let error = error {
                print("CompanionService: Send error to \(clientID) - \(error)")
            }
        })
    }
}

// MARK: - Protocol Framer

/// Custom framer for length-prefixed JSON messages
final class CompanionFramer: NWProtocolFramerImplementation {
    static let definition = NWProtocolFramer.Definition(implementation: CompanionFramer.self)
    static let label = "NetMonitor"

    required init(framer: NWProtocolFramer.Instance) {}

    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult {
        .ready
    }

    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        // Simple length-prefixed framing
        return 0
    }

    func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int, isComplete: Bool) {
        // Pass through
        do {
            try framer.writeOutputNoCopy(length: messageLength)
        } catch {
            print("Framer output error: \(error)")
        }
    }

    func wakeup(framer: NWProtocolFramer.Instance) {}
    func stop(framer: NWProtocolFramer.Instance) -> Bool { true }
    func cleanup(framer: NWProtocolFramer.Instance) {}
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor test -only-testing:NetMonitorTests/CompanionServiceTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add NetMonitor/Services/CompanionService.swift NetMonitorTests/Services/CompanionServiceTests.swift
git commit -m "$(cat <<'EOF'
feat: add CompanionService for Bonjour communication

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Companion Message Handlers

Implement handlers for processing commands from companion apps.

**Files:**
- Create: `NetMonitor/Services/CompanionMessageHandler.swift`

**Step 1: Write the CompanionMessageHandler**

```swift
// NetMonitor/Services/CompanionMessageHandler.swift
import Foundation
import SwiftData
import NetMonitorShared

/// Handles incoming messages from companion apps
@MainActor
final class CompanionMessageHandler {

    private let modelContext: ModelContext
    private let monitoringSession: MonitoringSession
    private let deviceDiscovery: DeviceDiscoveryCoordinator

    init(
        modelContext: ModelContext,
        monitoringSession: MonitoringSession,
        deviceDiscovery: DeviceDiscoveryCoordinator
    ) {
        self.modelContext = modelContext
        self.monitoringSession = monitoringSession
        self.deviceDiscovery = deviceDiscovery
    }

    /// Process an incoming message and return an optional response
    func handle(_ message: CompanionMessage, from clientID: UUID) async -> CompanionMessage? {
        switch message {
        case .command(let payload):
            return await handleCommand(payload)

        case .heartbeat:
            return .heartbeat(HeartbeatPayload())

        default:
            return nil
        }
    }

    /// Generate current status update message
    func generateStatusUpdate() -> CompanionMessage {
        let results = monitoringSession.latestResults.values
        let online = results.filter { $0.isReachable }.count
        let offline = results.filter { !$0.isReachable }.count
        let latencies = results.compactMap { $0.latency }
        let avgLatency = latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count)

        return .statusUpdate(StatusUpdatePayload(
            isMonitoring: monitoringSession.isMonitoring,
            onlineTargets: online,
            offlineTargets: offline,
            averageLatency: avgLatency
        ))
    }

    /// Generate target list message
    func generateTargetList() -> CompanionMessage {
        let descriptor = FetchDescriptor<NetworkTarget>()
        let targets = (try? modelContext.fetch(descriptor)) ?? []

        let targetInfos = targets.map { target in
            let measurement = monitoringSession.latestMeasurement(for: target)
            return TargetInfo(
                id: target.id,
                name: target.name,
                host: target.host,
                port: target.port,
                protocol: target.targetProtocol.rawValue,
                isEnabled: target.isEnabled,
                isReachable: measurement?.isReachable,
                latency: measurement?.latency
            )
        }

        return .targetList(TargetListPayload(targets: targetInfos))
    }

    /// Generate device list message
    func generateDeviceList() -> CompanionMessage {
        let deviceInfos = deviceDiscovery.discoveredDevices.map { device in
            DeviceInfo(
                id: device.id,
                ipAddress: device.ipAddress,
                macAddress: device.macAddress,
                hostname: device.hostname,
                vendor: device.vendor,
                deviceType: device.deviceType.rawValue,
                isOnline: device.isOnline
            )
        }

        return .deviceList(DeviceListPayload(devices: deviceInfos))
    }

    // MARK: - Private Methods

    private func handleCommand(_ payload: CommandPayload) async -> CompanionMessage? {
        switch payload.action {
        case .startMonitoring:
            await monitoringSession.startMonitoring()
            return generateStatusUpdate()

        case .stopMonitoring:
            monitoringSession.stopMonitoring()
            return generateStatusUpdate()

        case .scanDevices:
            deviceDiscovery.startScan()
            return .toolResult(ToolResultPayload(
                tool: "deviceScan",
                success: true,
                result: "Scan started"
            ))

        case .refreshTargets:
            return generateTargetList()

        case .refreshDevices:
            return generateDeviceList()

        case .ping:
            return await handlePingCommand(payload.parameters)

        case .wakeOnLan:
            return await handleWakeOnLan(payload.parameters)

        default:
            return .error(ErrorPayload(
                code: "UNSUPPORTED_COMMAND",
                message: "Command '\(payload.action.rawValue)' is not yet implemented"
            ))
        }
    }

    private func handlePingCommand(_ parameters: [String: String]?) async -> CompanionMessage {
        guard let host = parameters?["host"] else {
            return .error(ErrorPayload(
                code: "MISSING_PARAMETER",
                message: "Ping requires 'host' parameter"
            ))
        }

        // Create temporary target for ping
        let target = NetworkTarget(
            name: "Ping \(host)",
            host: host,
            port: nil,
            targetProtocol: .icmp,
            checkInterval: 5,
            timeout: 10,
            isEnabled: true
        )

        let service = ICMPMonitorService()

        do {
            let measurement = try await service.check(target: target)
            if measurement.isReachable, let latency = measurement.latency {
                return .toolResult(ToolResultPayload(
                    tool: "ping",
                    success: true,
                    result: "Reply from \(host): time=\(Int(latency))ms"
                ))
            } else {
                return .toolResult(ToolResultPayload(
                    tool: "ping",
                    success: false,
                    result: measurement.errorMessage ?? "No response from \(host)"
                ))
            }
        } catch {
            return .toolResult(ToolResultPayload(
                tool: "ping",
                success: false,
                result: "Ping failed: \(error.localizedDescription)"
            ))
        }
    }

    private func handleWakeOnLan(_ parameters: [String: String]?) async -> CompanionMessage {
        guard let mac = parameters?["mac"] else {
            return .error(ErrorPayload(
                code: "MISSING_PARAMETER",
                message: "Wake on LAN requires 'mac' parameter"
            ))
        }

        // TODO: Implement Wake on LAN
        return .toolResult(ToolResultPayload(
            tool: "wakeOnLan",
            success: false,
            result: "Wake on LAN not yet implemented for MAC: \(mac)"
        ))
    }
}
```

**Step 2: Build and verify no errors**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add NetMonitor/Services/CompanionMessageHandler.swift
git commit -m "$(cat <<'EOF'
feat: add CompanionMessageHandler for processing companion commands

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: Integration and Testing

Wire up all Phase 3 components and verify the complete flow.

**Files:**
- Modify: `NetMonitor/NetMonitorApp.swift`
- Modify: `NetMonitor/ContentView.swift`

**Step 1: Update NetMonitorApp with full Phase 3 integration**

```swift
// NetMonitor/NetMonitorApp.swift - Full updated version
import SwiftUI
import SwiftData

@main
struct NetMonitorApp: App {
    @State private var monitoringSession: MonitoringSession?
    @State private var deviceDiscovery: DeviceDiscoveryCoordinator?
    @State private var companionService: CompanionService?
    @State private var companionHandler: CompanionMessageHandler?
    @State private var menuBarController: MenuBarController?

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            NetworkTarget.self,
            TargetMeasurement.self,
            LocalDevice.self,
            SessionRecord.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(monitoringSession)
                .environment(deviceDiscovery)
                .onAppear {
                    Task { @MainActor in
                        await setupServices()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            if let session = monitoringSession {
                MenuBarCommands(
                    isMonitoring: .init(
                        get: { session.isMonitoring },
                        set: { _ in }
                    ),
                    startMonitoring: { await session.startMonitoring() },
                    stopMonitoring: { session.stopMonitoring() }
                )
            }
        }

        Settings {
            SettingsView()
        }
    }

    @MainActor
    private func setupServices() async {
        // 1. Set up monitoring session
        if monitoringSession == nil {
            monitoringSession = MonitoringSession(
                modelContainer: sharedModelContainer
            )
        }

        // 2. Set up device discovery
        if deviceDiscovery == nil {
            deviceDiscovery = DeviceDiscoveryCoordinator(
                modelContext: sharedModelContainer.mainContext
            )
        }

        // 3. Set up companion service
        if let session = monitoringSession,
           let discovery = deviceDiscovery,
           companionService == nil {
            companionHandler = CompanionMessageHandler(
                modelContext: sharedModelContainer.mainContext,
                monitoringSession: session,
                deviceDiscovery: discovery
            )

            companionService = CompanionService()

            do {
                try await companionService?.start { [weak companionHandler] message, clientID in
                    await companionHandler?.handle(message, from: clientID)
                }
            } catch {
                print("Failed to start companion service: \(error)")
            }
        }

        // 4. Set up menu bar
        if let session = monitoringSession, menuBarController == nil {
            menuBarController = MenuBarController(monitoringSession: session)
            menuBarController?.setup()
        }
    }
}
```

**Step 2: Update ContentView to pass environment objects**

```swift
// NetMonitor/ContentView.swift - Updated
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(MonitoringSession.self) private var monitoringSession: MonitoringSession?
    @Environment(DeviceDiscoveryCoordinator.self) private var deviceDiscovery: DeviceDiscoveryCoordinator?
    @State private var selectedSection: Section? = .dashboard

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSection)
        } detail: {
            switch selectedSection {
            case .dashboard:
                if let session = monitoringSession {
                    DashboardView()
                        .environment(session)
                } else {
                    ProgressView()
                }
            case .targets:
                TargetsView()
            case .devices:
                DevicesView()
            case .tools:
                ToolsView()
            case .settings:
                SettingsView()
            case nil:
                Text("Select a section")
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewContainer.shared.container)
        .environment(MonitoringSession(
            modelContainer: PreviewContainer.shared.container
        ))
}
```

**Step 3: Build the complete project**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor -configuration Debug build 2>&1 | tail -30`
Expected: BUILD SUCCEEDED

**Step 4: Run all tests**

Run: `xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor test 2>&1 | tail -40`
Expected: All tests pass

**Step 5: Final commit**

```bash
git add NetMonitor/NetMonitorApp.swift NetMonitor/ContentView.swift
git commit -m "$(cat <<'EOF'
feat: integrate Phase 3 components (discovery, menu bar, companion)

Phase 3 complete:
- Device discovery with ARP and Bonjour scanning
- Menu bar integration with quick stats
- Companion app communication via Bonjour service

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Summary

Phase 3 adds three major features to NetMonitor:

### 1. Device Discovery
- **ARPScannerService**: Scans local subnet via TCP probing and ARP cache
- **BonjourDiscoveryService**: Discovers mDNS services on the network
- **DeviceDiscoveryCoordinator**: Merges results, persists to SwiftData
- **MACVendorLookupService**: Identifies device vendors from OUI database
- **DevicesView/DeviceDetailView**: Full UI for browsing and managing devices

### 2. Menu Bar Integration
- **MenuBarController**: Manages NSStatusItem and popover lifecycle
- **MenuBarPopoverView**: Shows quick stats, online/offline counts, recent targets
- **MenuBarCommands**: Keyboard shortcuts (⇧⌘M for monitoring toggle)

### 3. Companion App Communication
- **CompanionMessage**: JSON protocol with typed message payloads
- **CompanionService**: Bonjour server on `_netmon._tcp` port 8849
- **CompanionMessageHandler**: Processes commands, generates responses

### Testing Strategy
Each service has focused unit tests for protocol compliance and state management. Integration is verified through build + full test suite runs.

### Next Steps (Phase 4)
- Network Tools implementation (Ping, Traceroute, Port Scanner, etc.)
- Settings view completion
- CloudKit sync for configurations
