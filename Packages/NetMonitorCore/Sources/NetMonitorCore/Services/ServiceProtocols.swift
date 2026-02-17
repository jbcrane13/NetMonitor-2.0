import Foundation
import NetworkScanKit

// MARK: - Supporting Types for Service Protocols

/// Result of a Wake-on-LAN magic packet transmission.
public struct WakeOnLANResult: Sendable {
    public let macAddress: String
    public let success: Bool
    public let error: String?
    public let sentAt: Date

    public init(macAddress: String, success: Bool, error: String? = nil) {
        self.macAddress = macAddress
        self.success = success
        self.error = error
        self.sentAt = Date()
    }
}

/// Result of a completed speed test run.
public struct SpeedTestData: Sendable {
    public let downloadSpeed: Double   // Mbps
    public let uploadSpeed: Double     // Mbps
    public let latency: Double         // ms
    public let jitter: Double?         // ms

    public init(downloadSpeed: Double, uploadSpeed: Double, latency: Double, jitter: Double? = nil) {
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.latency = latency
        self.jitter = jitter
    }
}

// MARK: - Top-Level Phase Enums

/// Speed test execution phases.
public enum SpeedTestPhase: String, Sendable {
    case idle
    case latency
    case download
    case upload
    case complete
}

/// Device discovery scan display phases.
public enum ScanDisplayPhase: String, Sendable {
    case idle       = ""
    case arpScan    = "Scanning network…"
    case tcpProbe   = "Probing ports…"
    case bonjour    = "Bonjour discovery…"
    case ssdp       = "UPnP discovery…"
    case icmpLatency = "Measuring latency…"
    case companion  = "Mac companion…"
    case resolving  = "Resolving names…"
    case done       = "Complete"
}

// MARK: - Service Protocols

/// Protocol for ping operations.
public protocol PingServiceProtocol: AnyObject, Sendable {
    func ping(host: String, count: Int, timeout: TimeInterval) async -> AsyncStream<PingResult>
    func stop() async
    func calculateStatistics(_ results: [PingResult], requestedCount: Int?) async -> PingStatistics?
}

/// Protocol for port scanning operations.
public protocol PortScannerServiceProtocol: AnyObject, Sendable {
    func scan(host: String, ports: [Int], timeout: TimeInterval) async -> AsyncStream<PortScanResult>
    func stop() async
}

/// Protocol for DNS lookup operations.
public protocol DNSLookupServiceProtocol: AnyObject {
    @MainActor var isLoading: Bool { get }
    @MainActor var lastError: String? { get }
    @MainActor func lookup(domain: String, recordType: DNSRecordType, server: String?) async -> DNSQueryResult?
}

/// Protocol for WHOIS lookup operations.
public protocol WHOISServiceProtocol: AnyObject, Sendable {
    func lookup(query: String) async throws -> WHOISResult
}

/// Protocol for Wake on LAN operations.
public protocol WakeOnLANServiceProtocol {
    @MainActor var isSending: Bool { get }
    @MainActor var lastResult: WakeOnLANResult? { get }
    @MainActor var lastError: String? { get }
    @MainActor func wake(macAddress: String, broadcastAddress: String, port: UInt16) async -> Bool
}

/// Protocol for speed test operations.
public protocol SpeedTestServiceProtocol {
    @MainActor var downloadSpeed: Double { get }
    @MainActor var uploadSpeed: Double { get }
    @MainActor var latency: Double { get }
    @MainActor var progress: Double { get }
    @MainActor var phase: SpeedTestPhase { get }
    @MainActor var isRunning: Bool { get }
    @MainActor var errorMessage: String? { get }
    @MainActor var duration: TimeInterval { get set }
    @MainActor func startTest() async throws -> SpeedTestData
    @MainActor func stopTest()
}

/// Protocol for network path monitoring.
public protocol NetworkMonitorServiceProtocol {
    @MainActor var isConnected: Bool { get }
    @MainActor var connectionType: ConnectionType { get }
    @MainActor var isExpensive: Bool { get }
    @MainActor var isConstrained: Bool { get }
    @MainActor var statusText: String { get }
    @MainActor func startMonitoring()
    @MainActor func stopMonitoring()
}

/// Protocol for device discovery (orchestrates NetworkScanKit).
public protocol DeviceDiscoveryServiceProtocol: AnyObject, Sendable {
    @MainActor var discoveredDevices: [DiscoveredDevice] { get }
    @MainActor var isScanning: Bool { get }
    @MainActor var scanProgress: Double { get }
    @MainActor var scanPhase: ScanDisplayPhase { get }
    @MainActor var lastScanDate: Date? { get }
    func scanNetwork(subnet: String?) async
    @MainActor func stopScan()
}

/// Protocol for default gateway detection.
public protocol GatewayServiceProtocol {
    @MainActor var gateway: GatewayInfo? { get }
    @MainActor var isLoading: Bool { get }
    @MainActor func detectGateway() async
}

/// Protocol for public IP / ISP lookup.
public protocol PublicIPServiceProtocol {
    @MainActor var ispInfo: ISPInfo? { get }
    @MainActor var isLoading: Bool { get }
    @MainActor func fetchPublicIP(forceRefresh: Bool) async
}

/// Protocol for WiFi info (implementation is platform-specific).
public protocol WiFiInfoServiceProtocol {
    @MainActor var currentWiFi: WiFiInfo? { get }
    @MainActor var isLocationAuthorized: Bool { get }
    @MainActor func requestLocationPermission()
    @MainActor func refreshWiFiInfo()
}

/// Protocol for Bonjour service discovery.
public protocol BonjourDiscoveryServiceProtocol: AnyObject, Sendable {
    @MainActor var discoveredServices: [BonjourService] { get }
    @MainActor var isDiscovering: Bool { get }
    @MainActor func discoveryStream(serviceType: String?) -> AsyncStream<BonjourService>
    @MainActor func startDiscovery(serviceType: String?)
    @MainActor func stopDiscovery()
    func resolveService(_ service: BonjourService) async -> BonjourService?
}

/// Protocol for traceroute operations.
public protocol TracerouteServiceProtocol: AnyObject, Sendable {
    func trace(host: String, maxHops: Int?, timeout: TimeInterval?) async -> AsyncStream<TracerouteHop>
    func stop() async
}

/// Protocol for MAC vendor lookup.
public protocol MACVendorLookupServiceProtocol: AnyObject, Sendable {
    func lookup(macAddress: String) async -> String?
}

/// Protocol for device hostname resolution.
public protocol DeviceNameResolverProtocol: Sendable {
    func resolve(ipAddress: String) async -> String?
}

// MARK: - Mac Companion Types

/// Connection state for the Mac companion service.
public enum MacConnectionState: Sendable, Equatable {
    case disconnected
    case browsing
    case connecting
    case connected
    case error(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// Minimal protocol for the Mac companion connection service.
/// Full implementation lives in platform targets (MacConnectionService on iOS,
/// CompanionService on macOS). Only the subset used by DeviceDiscoveryService
/// is required here.
@MainActor
public protocol MacConnectionServiceProtocol: AnyObject {
    var connectionState: MacConnectionState { get }
    var lastDeviceList: DeviceListPayload? { get }
    func send(command: CommandPayload) async
}
