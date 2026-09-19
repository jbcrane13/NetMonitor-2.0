import NetMonitorCore
import Foundation

// MARK: - Network Monitor Protocol

/// Protocol for network monitoring services (macOS-specific monitor actors).
/// Implementations must be actors for thread safety.
protocol NetworkMonitorService: Actor {
    func check(request: TargetCheckRequest) async throws -> MeasurementResult
}

// MARK: - NetworkMonitorError

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

// MARK: - TargetCheckRequest

/// Sendable value type for passing target info across actor boundaries.
struct TargetCheckRequest {
    let id: UUID
    let host: String
    let port: Int?
    let targetProtocol: TargetProtocol
    let timeout: TimeInterval
}

// MARK: - MeasurementResult

/// Sendable value type for returning measurement results across actor boundaries.
struct MeasurementResult {
    let targetID: UUID
    let timestamp: Date
    let latency: Double?
    let isReachable: Bool
    let errorMessage: String?
}

// MARK: - Local Device Discovery Support Types

/// Represents a device discovered on the local network — the macOS-local mirror of
/// `NetworkScanKit.DiscoveredDevice` that `DeviceDiscoveryCoordinator.mapDiscoveredDevices(_:)`
/// produces from the `ScanEngine` accumulator. `vendor`/`openPorts`/`latency` are filled by
/// the macOS enrichment phases (P2); `mergeDiscoveredDevices` writes each only when non-nil
/// so a sparse (pre-enrichment) merge cannot clear a value a later merge would supply.
struct LocalDiscoveredDevice: Equatable {
    let ipAddress: String
    let macAddress: String
    let hostname: String?
    let vendor: String?
    let openPorts: [Int]?
    let latency: Double?

    init(
        ipAddress: String,
        macAddress: String,
        hostname: String?,
        vendor: String? = nil,
        openPorts: [Int]? = nil,
        latency: Double? = nil
    ) {
        self.ipAddress = ipAddress
        self.macAddress = macAddress.uppercased()
        self.hostname = hostname
        self.vendor = vendor
        self.openPorts = openPorts
        self.latency = latency
    }
}

/// Errors that can occur during device discovery.
enum LocalDeviceDiscoveryError: Error {
    case networkUnavailable
    // periphery:ignore
    case permissionDenied
    // periphery:ignore
    case scanTimeout
    case invalidSubnet
}
