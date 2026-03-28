import Testing
import Foundation
import NetMonitorCore
import NetworkScanKit
@testable import NetMonitor_iOS

/// SharedServices.swift defines shared singleton extensions and retroactive
/// protocol conformances. These tests verify the service container wiring.

@MainActor
struct SharedServicesTests {

    // MARK: - Singleton availability

    @Test("NetworkMonitorService.shared is accessible")
    func networkMonitorSharedExists() {
        let service = NetworkMonitorService.shared
        _ = service
        // Verify it conforms to protocol
        let proto: any NetworkMonitorServiceProtocol = service
        _ = proto
    }

    @Test("NotificationService.shared is accessible")
    func notificationServiceSharedExists() {
        let service = NotificationService.shared
        _ = service
    }

    // MARK: - Retroactive conformance

    @Test("DeviceNameResolver conforms to DeviceNameResolverProtocol via retroactive conformance")
    func deviceNameResolverConformsToProtocol() {
        let resolver = DeviceNameResolver()
        let proto: any DeviceNameResolverProtocol = resolver
        _ = proto
    }

    // MARK: - Singleton identity

    @Test("NetworkMonitorService.shared returns same instance")
    func networkMonitorSharedIdentity() {
        let a = NetworkMonitorService.shared
        let b = NetworkMonitorService.shared
        #expect(a === b)
    }

    @Test("NotificationService.shared returns same instance")
    func notificationServiceSharedIdentity() {
        let a = NotificationService.shared
        let b = NotificationService.shared
        #expect(a === b)
    }

    // MARK: - NetworkMonitorService initial state

    @Test("NetworkMonitorService has sensible initial properties")
    func networkMonitorInitialState() {
        let service = NetworkMonitorService.shared
        // connectionType should have a valid value
        _ = service.connectionType
        _ = service.isConnected
        _ = service.isExpensive
        _ = service.isConstrained
    }
}
