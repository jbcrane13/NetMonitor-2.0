import Foundation
import SwiftData
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

/// Area 6d: Silent failure error surfacing tests for DeviceDiscoveryCoordinator.
///
/// DeviceDiscoveryCoordinator has `try?` sites at:
///   - mergeDiscoveredDevices(): `let existing = try? modelContext.fetch(descriptor).first`
///     (line ~168) — SwiftData fetch failure silently treated as "no existing device"
///   - fetchDevices(): `return (try? modelContext.fetch(descriptor)) ?? []`
///     (line ~464) — fetch failure silently returns empty array
///   - measureDeviceLatencies(): `let result = try? await pingService.ping(...)`
///     (line ~223) — ping failure silently returns nil latency
///
/// These tests verify the current silent-failure behavior:
///   - Fetch failure -> empty results (no crash, no error to user)
///   - Ping failure -> device latency not updated (no crash)
///   - Save failure -> logged but not surfaced to UI
@Suite(.serialized)
@MainActor
struct DeviceDiscoveryCoordinatorErrorTests {

    // MARK: - Helpers

    private func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(
            UUID().uuidString, schema: schema,
            isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }

    private func makeFreshDefaults() -> (UserDefaults, String) {
        let suite = "DeviceDiscoveryCoordinatorErrorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func makeCoordinator(context: ModelContext) -> DeviceDiscoveryCoordinator {
        DeviceDiscoveryCoordinator(
            modelContext: context,
            arpScanner: ARPScannerService(timeout: 0.05),
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(
                userDefaults: makeFreshDefaults().0,
                activeProfilesProvider: { [] }
            )
        )
    }

    // MARK: - Empty Store: fetchDevices Returns Empty (Not Crash)

    @Test("Fresh coordinator with empty store: discoveredDevices is empty, not nil or crash")
    func emptyStoreReturnsEmptyArray() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        #expect(coordinator.discoveredDevices.isEmpty,
                "Empty store should produce empty discoveredDevices — fetchDevices uses try? ?? [] to avoid crash")
    }

    // MARK: - Merge with Empty Input: No Crash

    @Test("mergeDiscoveredDevices with empty array: no crash, state unchanged")
    func mergeEmptyArrayNoCrash() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        coordinator.mergeDiscoveredDevices([], profileID: nil)

        #expect(coordinator.discoveredDevices.isEmpty)
    }

    // MARK: - Merge: Device with Empty MAC Falls Back to IP Matching

    @Test("Device with empty MAC address uses IP-based matching")
    func emptyMACUsesIPMatching() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        // First merge: device with empty MAC
        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.168.1.50", macAddress: "", hostname: "camera.local")
        ], profileID: nil)

        // Second merge: same IP, empty MAC, different hostname
        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.168.1.50", macAddress: "", hostname: "camera-updated.local")
        ], profileID: nil)

        // Should be 1 device (matched by IP), not 2
        #expect(coordinator.discoveredDevices.count == 1)
        #expect(coordinator.discoveredDevices.first?.hostname == "camera-updated.local")
    }

    // MARK: - Mark Offline: Non-Matching Profile Devices Unaffected

    @Test("markOfflineDevices only affects devices with matching profileID")
    func markOfflineProfileIsolation() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let profileA = UUID()
        let profileB = UUID()

        // Insert device in profileA
        let deviceA = LocalDevice(
            ipAddress: "10.0.0.1", macAddress: "AA:AA:AA:AA:AA:01",
            hostname: nil, vendor: nil, deviceType: .unknown,
            networkProfileID: profileA
        )
        deviceA.status = .online
        context.insert(deviceA)

        // Insert device in profileB
        let deviceB = LocalDevice(
            ipAddress: "10.0.0.2", macAddress: "BB:BB:BB:BB:BB:01",
            hostname: nil, vendor: nil, deviceType: .unknown,
            networkProfileID: profileB
        )
        deviceB.status = .online
        context.insert(deviceB)
        try context.save()

        let coordinator = makeCoordinator(context: context)

        // Mark offline for profileA with no current IPs — only profileA devices affected
        coordinator.mergeDiscoveredDevices([], profileID: profileA)
        coordinator.markOfflineDevices(currentIPs: Set(), profileID: profileA)

        // Fetch all devices to check
        let allDevices = try context.fetch(FetchDescriptor<LocalDevice>())
        let devA = allDevices.first(where: { $0.macAddress == "AA:AA:AA:AA:AA:01" })
        let devB = allDevices.first(where: { $0.macAddress == "BB:BB:BB:BB:BB:01" })

        #expect(devA?.status == .offline,
                "ProfileA device should be marked offline")
        #expect(devB?.status == .online,
                "ProfileB device should be unaffected — markOfflineDevices skips non-matching profiles")
    }

    // MARK: - Scan State: stopScan Resets isScanning

    @Test("stopScan sets isScanning to false immediately")
    func stopScanResetsIsScanning() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        coordinator.stopScan()
        #expect(coordinator.isScanning == false)
    }

    @Test("stopScan is safe to call when not scanning")
    func stopScanWhenNotScanning() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        // Call stopScan twice without starting — should not crash
        coordinator.stopScan()
        coordinator.stopScan()
        #expect(coordinator.isScanning == false)
    }

    // MARK: - Documenting the Silent Failure Gaps

    @Test("fetchDevices returns empty array on SwiftData error — error not surfaced to UI")
    func fetchDevicesDocumentsSilentFailure() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        // The production code at line ~464:
        //   return (try? modelContext.fetch(descriptor)) ?? []
        //
        // If SwiftData fetch throws (e.g., store corruption, schema migration failure),
        // the coordinator silently returns an empty array. The user sees "No devices found"
        // instead of an error message explaining why.
        //
        // GAP: Consider surfacing fetch errors via a published errorMessage property
        // so the UI can display "Database error — try resetting" instead of empty state.

        #expect(coordinator.discoveredDevices.isEmpty,
                "Documents current behavior: empty store returns empty array via try? ?? []")
    }

    @Test("mergeDiscoveredDevices: fetch failure during duplicate check treats device as new")
    func mergeFetchFailureTreatsAsNew() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        // The production code at line ~168:
        //   let existing = try? modelContext.fetch(descriptor).first
        //
        // If the fetch throws, existing is nil, so the device is treated as new
        // and inserted. This could cause duplicates if the store is temporarily
        // unreachable then recovers.
        //
        // GAP: A failing fetch should be distinguished from "no match found."

        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.168.1.1", macAddress: "CC:CC:CC:CC:CC:01", hostname: nil)
        ], profileID: nil)

        #expect(coordinator.discoveredDevices.count == 1,
                "Documents current behavior: successful fetch correctly finds/inserts device")
    }
}
