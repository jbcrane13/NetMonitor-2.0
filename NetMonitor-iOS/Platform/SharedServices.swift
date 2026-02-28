import Foundation
import NetMonitorCore
import NetworkScanKit

// MARK: - Shared Service Singletons

extension NetworkMonitorService {
    /// Platform-level shared instance. Started once at app launch.
    static let shared: NetworkMonitorService = .init()
}

extension NotificationService {
    /// Shared notification service for the app lifecycle.
    static let shared = NotificationService()
}

// MARK: - Retroactive Conformances

/// DeviceNameResolver lives in NetworkScanKit; DeviceNameResolverProtocol lives in NetMonitorCore.
/// This conformance bridges the two packages.
extension DeviceNameResolver: @retroactive DeviceNameResolverProtocol {}
