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
struct TargetCheckRequest: Sendable {
    let id: UUID
    let host: String
    let port: Int?
    let targetProtocol: TargetProtocol
    let timeout: TimeInterval
}

// MARK: - MeasurementResult

/// Sendable value type for returning measurement results across actor boundaries.
struct MeasurementResult: Sendable {
    let targetID: UUID
    let timestamp: Date
    let latency: Double?
    let isReachable: Bool
    let errorMessage: String?
}

// MARK: - Local Device Discovery Support Types

/// Represents a device discovered on the local network (macOS ARP scanner output).
struct LocalDiscoveredDevice: Sendable, Equatable {
    let ipAddress: String
    let macAddress: String
    let hostname: String?

    init(ipAddress: String, macAddress: String, hostname: String?) {
        self.ipAddress = ipAddress
        self.macAddress = macAddress.uppercased()
        self.hostname = hostname
    }
}

/// Errors that can occur during device discovery.
enum LocalDeviceDiscoveryError: Error, Sendable {
    case networkUnavailable
    // periphery:ignore
    case permissionDenied
    // periphery:ignore
    case scanTimeout
    case invalidSubnet
}

/// Protocol for local ARP-based device discovery services.
protocol LocalDeviceScanner: Actor {
    // periphery:ignore
    func scanNetwork(interface: String?) async throws -> [LocalDiscoveredDevice]
    // periphery:ignore
    func stopScan()
    // periphery:ignore
    var isScanning: Bool { get }
}
