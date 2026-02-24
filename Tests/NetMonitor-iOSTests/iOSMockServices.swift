import Foundation
import NetMonitorCore
import NetworkScanKit

// MARK: - Mock Ping Service

final class MockPingService: PingServiceProtocol, @unchecked Sendable {
    var mockResults: [PingResult] = []
    var mockStatistics: PingStatistics?
    var pingCallCount = 0
    var stopCallCount = 0

    func ping(host: String, count: Int, timeout: TimeInterval) async -> AsyncStream<PingResult> {
        pingCallCount += 1
        let results = mockResults
        return AsyncStream { continuation in
            for result in results { continuation.yield(result) }
            continuation.finish()
        }
    }

    func stop() async { stopCallCount += 1 }

    func calculateStatistics(_ results: [PingResult], requestedCount: Int?) async -> PingStatistics? {
        return mockStatistics
    }
}

// MARK: - Mock Traceroute Service

final class MockTracerouteService: TracerouteServiceProtocol, @unchecked Sendable {
    var mockHops: [TracerouteHop] = []
    var traceCallCount = 0
    var stopCallCount = 0

    func trace(host: String, maxHops: Int?, timeout: TimeInterval?) async -> AsyncStream<TracerouteHop> {
        traceCallCount += 1
        let hops = mockHops
        return AsyncStream { continuation in
            for hop in hops { continuation.yield(hop) }
            continuation.finish()
        }
    }

    func stop() async { stopCallCount += 1 }
}

// MARK: - Mock DNS Lookup Service

@MainActor
final class MockDNSLookupService: DNSLookupServiceProtocol {
    var isLoading: Bool = false
    var lastError: String? = nil
    var mockResult: DNSQueryResult?

    func lookup(domain: String, recordType: DNSRecordType, server: String?) async -> DNSQueryResult? {
        return mockResult
    }
}

// MARK: - Mock WHOIS Service

final class MockWHOISService: WHOISServiceProtocol, @unchecked Sendable {
    var mockResult: WHOISResult?
    var shouldThrow = false
    var thrownError: Error = URLError(.badServerResponse)

    func lookup(query: String) async throws -> WHOISResult {
        if shouldThrow { throw thrownError }
        return mockResult ?? WHOISResult(query: query, rawData: "")
    }
}

// MARK: - Mock Wake on LAN Service

@MainActor
final class MockWakeOnLANService: WakeOnLANServiceProtocol {
    var isSending: Bool = false
    var lastResult: WakeOnLANResult? = nil
    var lastError: String? = nil
    var shouldSucceed = true

    func wake(macAddress: String, broadcastAddress: String, port: UInt16) async -> Bool {
        lastResult = WakeOnLANResult(
            macAddress: macAddress,
            success: shouldSucceed,
            error: shouldSucceed ? nil : "Mock error"
        )
        if !shouldSucceed { lastError = "Mock error" }
        return shouldSucceed
    }
}

// MARK: - Mock Port Scanner Service

final class MockPortScannerService: PortScannerServiceProtocol, @unchecked Sendable {
    var mockResults: [PortScanResult] = []
    var stopCallCount = 0

    func scan(host: String, ports: [Int], timeout: TimeInterval) async -> AsyncStream<PortScanResult> {
        let results = mockResults
        return AsyncStream { continuation in
            for result in results { continuation.yield(result) }
            continuation.finish()
        }
    }

    func stop() async { stopCallCount += 1 }
}

// MARK: - Mock Bonjour Discovery Service

@MainActor
final class MockBonjourDiscoveryService: BonjourDiscoveryServiceProtocol, @unchecked Sendable {
    var discoveredServices: [BonjourService] = []
    var isDiscovering: Bool = false
    var startCallCount = 0
    var stopCallCount = 0
    var mockStreamServices: [BonjourService] = []

    func discoveryStream(serviceType: String?) -> AsyncStream<BonjourService> {
        let services = mockStreamServices
        return AsyncStream { continuation in
            for service in services { continuation.yield(service) }
            continuation.finish()
        }
    }

    func startDiscovery(serviceType: String?) {
        startCallCount += 1
        isDiscovering = true
    }

    func stopDiscovery() {
        stopCallCount += 1
        isDiscovering = false
    }

    nonisolated func resolveService(_ service: BonjourService) async -> BonjourService? {
        return service
    }
}

// MARK: - Mock Speed Test Service

@MainActor
final class MockSpeedTestService: SpeedTestServiceProtocol {
    var downloadSpeed: Double = 0
    var uploadSpeed: Double = 0
    var latency: Double = 0
    var progress: Double = 0
    var phase: SpeedTestPhase = .idle
    var isRunning: Bool = false
    var errorMessage: String? = nil
    var duration: TimeInterval = 5.0
    var mockResult: SpeedTestData?
    var shouldThrow = false
    var stopCallCount = 0

    func startTest() async throws -> SpeedTestData {
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        return mockResult ?? SpeedTestData(downloadSpeed: 100, uploadSpeed: 50, latency: 20)
    }

    func stopTest() {
        isRunning = false
        phase = .idle
        stopCallCount += 1
    }
}

// MARK: - Mock Network Monitor Service

@MainActor
final class MockNetworkMonitorService: NetworkMonitorServiceProtocol {
    var isConnected: Bool = true
    var connectionType: ConnectionType = .wifi
    var isExpensive: Bool = false
    var isConstrained: Bool = false
    var statusText: String = "Connected via Wi-Fi"

    func startMonitoring() {}
    func stopMonitoring() {}
}

// MARK: - Mock WiFi Info Service

@MainActor
final class MockWiFiInfoService: WiFiInfoServiceProtocol {
    var currentWiFi: WiFiInfo? = nil
    var isLocationAuthorized: Bool = true
    var refreshCallCount = 0

    func requestLocationPermission() {}
    func refreshWiFiInfo() { refreshCallCount += 1 }
}

// MARK: - Mock Gateway Service

@MainActor
final class MockGatewayService: GatewayServiceProtocol {
    var gateway: GatewayInfo? = nil
    var isLoading: Bool = false
    var detectCallCount = 0

    func detectGateway() async { detectCallCount += 1 }
}

// MARK: - Mock Public IP Service

@MainActor
final class MockPublicIPService: PublicIPServiceProtocol {
    var ispInfo: ISPInfo? = nil
    var isLoading: Bool = false
    var fetchCallCount = 0

    func fetchPublicIP(forceRefresh: Bool) async { fetchCallCount += 1 }
}

// MARK: - Mock Device Discovery Service

@MainActor
final class MockDeviceDiscoveryService: DeviceDiscoveryServiceProtocol, @unchecked Sendable {
    var discoveredDevices: [DiscoveredDevice] = []
    var isScanning: Bool = false
    var scanProgress: Double = 0.0
    var scanPhase: ScanDisplayPhase = .idle
    var lastScanDate: Date? = nil
    var scanCallCount = 0
    var lastScannedSubnet: String? = nil
    var lastScannedProfile: NetMonitorCore.NetworkProfile? = nil

    func scanNetwork(subnet: String?) async {
        scanCallCount += 1
        lastScannedSubnet = subnet
    }

    func scanNetwork(profile: NetMonitorCore.NetworkProfile?) async {
        scanCallCount += 1
        lastScannedProfile = profile
    }

    func cachedDevices(for profile: NetMonitorCore.NetworkProfile?) -> [DiscoveredDevice] {
        discoveredDevices
    }

    func stopScan() {}
}

// MARK: - Mock Mac Connection Service

@MainActor
final class MockMacConnectionService: MacConnectionServiceProtocol {
    var connectionState: MacConnectionState = .disconnected
    var lastDeviceList: DeviceListPayload? = nil
    var connectedMacName: String? = nil
    var isBrowsing: Bool = false
    var discoveredMacs: [DiscoveredMac] = []

    func send(command: CommandPayload) async {}
}
