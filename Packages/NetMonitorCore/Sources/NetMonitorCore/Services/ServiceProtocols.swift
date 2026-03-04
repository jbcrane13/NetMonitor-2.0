import CoreLocation
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
    public let serverName: String?     // optional test server name

    public init(downloadSpeed: Double, uploadSpeed: Double, latency: Double, jitter: Double? = nil, serverName: String? = nil) {
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.latency = latency
        self.jitter = jitter
        self.serverName = serverName
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
    @MainActor var peakDownloadSpeed: Double { get }
    @MainActor var peakUploadSpeed: Double { get }
    @MainActor var latency: Double { get }
    @MainActor var jitter: Double { get }
    @MainActor var progress: Double { get }
    @MainActor var phase: SpeedTestPhase { get }
    @MainActor var isRunning: Bool { get }
    @MainActor var errorMessage: String? { get }
    @MainActor var duration: TimeInterval { get set }
    /// The server to use for the next test run. `nil` means auto-select (Cloudflare default).
    @MainActor var selectedServer: SpeedTestServer? { get set }
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
    @MainActor func cachedDevices(for profile: NetworkProfile?) -> [DiscoveredDevice]
    func scanNetwork(subnet: String?) async
    func scanNetwork(profile: NetworkProfile?) async
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
    @MainActor var authorizationStatus: CLAuthorizationStatus { get }
    @MainActor func requestLocationPermission()
    @MainActor func refreshWiFiInfo()
    @MainActor func fetchCurrentWiFi() async -> WiFiInfo?
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

// MARK: - New Feature Supporting Types

/// Result of a subnet calculation.
public struct SubnetInfo: Sendable {
    public let cidr: String
    public let networkAddress: String
    public let broadcastAddress: String
    public let subnetMask: String
    public let firstHost: String
    public let lastHost: String
    public let usableHosts: Int
    public let prefixLength: Int

    public init(cidr: String, networkAddress: String, broadcastAddress: String, subnetMask: String, firstHost: String, lastHost: String, usableHosts: Int, prefixLength: Int) {
        self.cidr = cidr
        self.networkAddress = networkAddress
        self.broadcastAddress = broadcastAddress
        self.subnetMask = subnetMask
        self.firstHost = firstHost
        self.lastHost = lastHost
        self.usableHosts = usableHosts
        self.prefixLength = prefixLength
    }
}

/// A single location result from a world ping check.
public struct WorldPingLocationResult: Sendable, Identifiable {
    public let id: String
    public let country: String
    public let city: String
    public let latencyMs: Double?
    public let isSuccess: Bool
    /// Resolved IP address seen by this probe (reveals anycast/CDN distribution).
    public let resolvedAddress: String?
    /// HTTP status code (nil for ICMP-only measurements).
    public let httpStatus: Int?

    public init(
        id: String,
        country: String,
        city: String,
        latencyMs: Double?,
        isSuccess: Bool,
        resolvedAddress: String? = nil,
        httpStatus: Int? = nil
    ) {
        self.id = id
        self.country = country
        self.city = city
        self.latencyMs = latencyMs
        self.isSuccess = isSuccess
        self.resolvedAddress = resolvedAddress
        self.httpStatus = httpStatus
    }
}

/// Geographic location info for an IP address.
public struct GeoLocation: Sendable {
    public let ip: String
    public let country: String
    public let countryCode: String
    public let region: String
    public let city: String
    public let latitude: Double
    public let longitude: Double
    public let isp: String?

    public init(ip: String, country: String, countryCode: String, region: String, city: String, latitude: Double, longitude: Double, isp: String? = nil) {
        self.ip = ip
        self.country = country
        self.countryCode = countryCode
        self.region = region
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
        self.isp = isp
    }
}

/// SSL certificate information for a domain.
public struct SSLCertificateInfo: Sendable {
    public let domain: String
    public let issuer: String
    public let subject: String
    public let validFrom: Date
    public let validTo: Date
    public let isValid: Bool
    public let daysUntilExpiry: Int

    public init(domain: String, issuer: String, subject: String, validFrom: Date, validTo: Date, isValid: Bool, daysUntilExpiry: Int) {
        self.domain = domain
        self.issuer = issuer
        self.subject = subject
        self.validFrom = validFrom
        self.validTo = validTo
        self.isValid = isValid
        self.daysUntilExpiry = daysUntilExpiry
    }
}

/// Aggregated network health score.
public struct NetworkHealthScore: Sendable {
    public let score: Int          // 0-100
    public let grade: String       // A/B/C/D/F
    public let latencyMs: Double?
    public let packetLoss: Double?
    public let downloadSpeed: Double?
    public let uploadSpeed: Double?
    public let details: [String: String]

    public init(score: Int, grade: String, latencyMs: Double? = nil, packetLoss: Double? = nil, downloadSpeed: Double? = nil, uploadSpeed: Double? = nil, details: [String: String] = [:]) {
        self.score = score
        self.grade = grade
        self.latencyMs = latencyMs
        self.packetLoss = packetLoss
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.details = details
    }
}

/// Difference between two consecutive network scans.
public struct ScanDiff: Sendable {
    public let newDevices: [DiscoveredDevice]
    public let removedDevices: [DiscoveredDevice]
    public let changedDevices: [DiscoveredDevice]
    public let scannedAt: Date

    public init(newDevices: [DiscoveredDevice], removedDevices: [DiscoveredDevice], changedDevices: [DiscoveredDevice], scannedAt: Date = Date()) {
        self.newDevices = newDevices
        self.removedDevices = removedDevices
        self.changedDevices = changedDevices
        self.scannedAt = scannedAt
    }
}

// MARK: - New Feature Service Protocols

/// Protocol for subnet calculation.
public protocol SubnetCalculatorServiceProtocol: AnyObject, Sendable {
    func calculate(cidr: String) -> SubnetInfo?
}

/// Protocol for world ping (global latency checks via external API).
public protocol WorldPingServiceProtocol: AnyObject, Sendable {
    var lastError: String? { get }
    func ping(host: String, maxNodes: Int) async -> AsyncStream<WorldPingLocationResult>
}

/// Protocol for IP geolocation lookup.
public protocol GeoLocationServiceProtocol: AnyObject, Sendable {
    func lookup(ip: String) async throws -> GeoLocation
}

/// Protocol for SSL certificate inspection.
public protocol SSLCertificateServiceProtocol: AnyObject, Sendable {
    func checkCertificate(domain: String) async throws -> SSLCertificateInfo
}

/// Protocol for computing an overall network health score.
public protocol NetworkHealthScoreServiceProtocol: AnyObject, Sendable {
    func calculateScore() async -> NetworkHealthScore
}

/// Protocol for scheduling recurring scans and detecting changes.
@MainActor
public protocol ScanSchedulerServiceProtocol: AnyObject, Sendable {
    func scheduleNextScan(interval: TimeInterval)
    func getLastScanDiff() -> ScanDiff?
    /// Compare `current` devices against the stored baseline and return the diff.
    func computeDiff(current: [DiscoveredDevice]) -> ScanDiff
}

// MARK: - Heatmap Service Protocol

/// Protocol for WiFi heatmap measurement operations.
/// Platform implementations provide passive WiFi data collection,
/// active speed/latency measurement, and continuous streaming.
public protocol HeatmapServiceProtocol: AnyObject, Sendable {
    /// Takes a single passive WiFi measurement (RSSI, SSID, BSSID, channel, band, noise floor).
    func takeMeasurement(at floorPlanX: Double, floorPlanY: Double) async -> MeasurementPoint

    /// Takes an active measurement: passive data plus speed test and ping.
    func takeActiveMeasurement(at floorPlanX: Double, floorPlanY: Double) async -> MeasurementPoint

    /// Starts continuous passive measurements at the specified interval.
    /// Returns an AsyncStream that yields measurements until stopped.
    func startContinuousMeasurement(interval: TimeInterval) async -> AsyncStream<MeasurementPoint>

    /// Stops any in-progress continuous measurement stream.
    func stopContinuousMeasurement() async
}

// MARK: - SSL / Domain Expiration Types

/// Aggregated expiration status for a tracked domain (SSL cert + WHOIS registrar data).
public struct DomainExpirationStatus: Sendable, Identifiable {
    public let id: String
    public let domain: String
    public let port: Int
    public let notes: String?
    public let sslCertificate: SSLCertificateInfo?
    public let sslError: String?
    public let whoisResult: WHOISResult?
    public let whoisError: String?

    public init(
        domain: String,
        port: Int,
        notes: String? = nil,
        sslCertificate: SSLCertificateInfo? = nil,
        sslError: String? = nil,
        whoisResult: WHOISResult? = nil,
        whoisError: String? = nil
    ) {
        self.id = "\(domain):\(port)"
        self.domain = domain
        self.port = port
        self.notes = notes
        self.sslCertificate = sslCertificate
        self.sslError = sslError
        self.whoisResult = whoisResult
        self.whoisError = whoisError
    }

    public var sslDaysUntilExpiration: Int? { sslCertificate?.daysUntilExpiry }

    public var domainDaysUntilExpiration: Int? {
        guard let expDate = whoisResult?.expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expDate).day.map { max(0, $0) }
    }
}

/// Protocol for tracking SSL certificate and domain expiration across multiple domains.
public protocol CertificateExpirationTrackerProtocol: AnyObject, Sendable {
    func addDomain(_ domain: String, port: Int?, notes: String?) async
    func removeDomain(_ domain: String) async
    func refreshDomain(_ domain: String) async -> DomainExpirationStatus?
    func refreshAllDomains() async -> [DomainExpirationStatus]
    func getAllTrackedDomains() async -> [DomainExpirationStatus]
    func getExpiringDomains(daysThreshold: Int) async -> [DomainExpirationStatus]
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
    /// The name of the currently connected Mac (nil when not connected).
    var connectedMacName: String? { get }
    /// Whether the service is currently browsing for Macs.
    var isBrowsing: Bool { get }
    /// Macs discovered on the local network (visible for UI pairing).
    var discoveredMacs: [DiscoveredMac] { get }
    func send(command: CommandPayload) async
}

/// Minimal representation of a discovered Mac peer on the LAN.
public struct DiscoveredMac: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public static func == (lhs: DiscoveredMac, rhs: DiscoveredMac) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}
