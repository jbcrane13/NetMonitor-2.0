import Foundation
import SwiftData
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

/// Tests covering the loadPersistedDevices → discoveredDevices pipeline and
/// save/fetch behavior under various SwiftData store conditions.
///
/// Specifically exercises the code paths at:
/// - Line 167: `let existing = try? modelContext.fetch(descriptor).first`
/// - Line 463: `return (try? modelContext.fetch(descriptor)) ?? []`
/// - The save + reload loop inside mergeDiscoveredDevices / markOfflineDevices
@MainActor
struct DeviceDiscoveryCoordinatorSaveErrorTests {

    // MARK: - Helpers

    private func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
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

    private func makeFreshDefaults() -> (UserDefaults, String) {
        let suite = "DeviceDiscoveryCoordinatorSaveErrorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    // MARK: - Baseline: Empty Store

    @Test("loadPersistedDevices on empty store populates discoveredDevices as empty array")
    func freshContextYieldsEmptyDiscoveredDevices() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        // The coordinator calls loadPersistedDevices in init; store is empty.
        #expect(coordinator.discoveredDevices.isEmpty)
    }

    // MARK: - Merge then Fetch Reflects Updated State

    @Test("discoveredDevices reflects persisted count after mergeDiscoveredDevices")
    func discoveredDevicesCountMatchesPersistedAfterMerge() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "10.0.0.1", macAddress: "AA:BB:CC:00:00:01", hostname: nil),
            LocalDiscoveredDevice(ipAddress: "10.0.0.2", macAddress: "AA:BB:CC:00:00:02", hostname: nil),
            LocalDiscoveredDevice(ipAddress: "10.0.0.3", macAddress: "AA:BB:CC:00:00:03", hostname: nil),
        ], profileID: nil)

        // mergeDiscoveredDevices calls loadPersistedDevices at the end,
        // so discoveredDevices must reflect the three inserted records.
        #expect(coordinator.discoveredDevices.count == 3)
    }

    @Test("discoveredDevices IPs match what was merged into the store")
    func discoveredDevicesIPsMatchMergedInput() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        let inputIPs = ["192.168.1.10", "192.168.1.20", "192.168.1.30"]
        coordinator.mergeDiscoveredDevices(
            inputIPs.enumerated().map { idx, ip in
                LocalDiscoveredDevice(ipAddress: ip, macAddress: "BB:BB:BB:BB:BB:0\(idx)", hostname: nil)
            },
            profileID: nil
        )

        let resultIPs = Set(coordinator.discoveredDevices.map(\.ipAddress))
        for ip in inputIPs {
            #expect(resultIPs.contains(ip), "Expected \(ip) in discoveredDevices")
        }
    }

    // MARK: - Pre-existing Store Devices Load at Init

    @Test("coordinator loads pre-existing devices from store at init time")
    func coordinatorLoadsPreExistingDevicesAtInit() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        // Seed the store before the coordinator is created.
        let device1 = LocalDevice(
            ipAddress: "172.16.0.10",
            macAddress: "CC:CC:CC:CC:CC:01",
            hostname: "seedhost1"
        )
        let device2 = LocalDevice(
            ipAddress: "172.16.0.11",
            macAddress: "CC:CC:CC:CC:CC:02",
            hostname: "seedhost2"
        )
        context.insert(device1)
        context.insert(device2)
        try context.save()

        // Creating the coordinator calls loadPersistedDevices in init.
        let coordinator = makeCoordinator(context: context)

        #expect(coordinator.discoveredDevices.count == 2)
        let ips = Set(coordinator.discoveredDevices.map(\.ipAddress))
        #expect(ips.contains("172.16.0.10"))
        #expect(ips.contains("172.16.0.11"))
    }

    // MARK: - Profile-Scoped Fetch Isolation

    @Test("loadPersistedDevices only surfaces devices for the active profile")
    func fetchIsolatedByProfileID() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let profileA = UUID()
        let profileB = UUID()

        // Insert devices for two distinct profiles directly into the store.
        let devA = LocalDevice(
            ipAddress: "10.1.0.1",
            macAddress: "DA:DA:DA:DA:DA:01",
            hostname: nil,
            vendor: nil,
            deviceType: .unknown,
            networkProfileID: profileA
        )
        let devB = LocalDevice(
            ipAddress: "10.2.0.1",
            macAddress: "DB:DB:DB:DB:DB:01",
            hostname: nil,
            vendor: nil,
            deviceType: .unknown,
            networkProfileID: profileB
        )
        context.insert(devA)
        context.insert(devB)
        try context.save()

        // Coordinator targeting profileA should only see devA.
        let coordinator = makeCoordinator(context: context)
        coordinator.mergeDiscoveredDevices([], profileID: profileA)

        let ips = Set(coordinator.discoveredDevices.map(\.ipAddress))
        #expect(ips.contains("10.1.0.1"))
        #expect(!ips.contains("10.2.0.1"),
                "Profile B device must not leak into profile A results")
    }

    // MARK: - Mark-Offline Reload

    @Test("markOfflineDevices triggers reload, leaving discoveredDevices consistent with store")
    func markOfflineTriggersReload() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.168.5.1", macAddress: "EE:EE:EE:00:00:01", hostname: nil),
            LocalDiscoveredDevice(ipAddress: "192.168.5.2", macAddress: "EE:EE:EE:00:00:02", hostname: nil),
        ], profileID: nil)

        // Only keep .1 in the current scan; .2 should be marked offline.
        coordinator.markOfflineDevices(currentIPs: Set(["192.168.5.1"]), profileID: nil)

        // discoveredDevices is reloaded inside markOfflineDevices — verify count unchanged
        // but status differs.
        #expect(coordinator.discoveredDevices.count == 2)

        let device1 = coordinator.discoveredDevices.first(where: { $0.ipAddress == "192.168.5.1" })
        let device2 = coordinator.discoveredDevices.first(where: { $0.ipAddress == "192.168.5.2" })
        #expect(device1?.status == .online)
        #expect(device2?.status == .offline)
    }

    // MARK: - Sequential Merges Stay Deduplicated

    @Test("sequential merges for the same MAC address do not duplicate discoveredDevices")
    func sequentialMergesDoNotDuplicateDevices() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        let mac = "FF:FF:FF:FF:FF:01"
        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "10.0.1.1", macAddress: mac, hostname: nil),
        ], profileID: nil)
        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "10.0.1.1", macAddress: mac, hostname: "updated.local"),
        ], profileID: nil)

        // Should still be exactly one device for this MAC.
        let matching = coordinator.discoveredDevices.filter { $0.macAddress == mac }
        #expect(matching.count == 1)
        #expect(matching.first?.hostname == "updated.local")
    }

    // MARK: - Large Merge Batch

    @Test("large batch merge correctly persists all devices and reloads them")
    func largeBatchMerge() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        let batchSize = 50
        let devices = (1...batchSize).map { idx in
            LocalDiscoveredDevice(
                ipAddress: "10.0.\(idx / 256).\(idx % 256)",
                macAddress: String(format: "AA:AA:AA:AA:%02X:%02X", idx / 256, idx % 256),
                hostname: "host-\(idx).local"
            )
        }

        coordinator.mergeDiscoveredDevices(devices, profileID: nil)

        #expect(coordinator.discoveredDevices.count == batchSize)
    }

    // MARK: - Nil profileID → no-profile devices are scoped correctly

    @Test("nil profileID devices are not returned when querying by explicit profileID")
    func nilProfileDevicesDoNotAppearInProfileQuery() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        // Insert a device with nil profileID.
        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.1", macAddress: "00:11:22:33:44:55", hostname: nil),
        ], profileID: nil)

        // Merge for a specific profile — nil-profile devices must not appear.
        let specificProfile = UUID()
        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.3.1", macAddress: "66:77:88:99:AA:BB", hostname: nil),
        ], profileID: specificProfile)

        let profileIPs = Set(coordinator.discoveredDevices.map(\.ipAddress))
        #expect(profileIPs.contains("192.0.3.1"))
        #expect(!profileIPs.contains("192.0.2.1"),
                "nil-profile device must not appear in specific-profile discoveredDevices")
    }
}
