import Foundation
import SwiftData
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

@Suite("DeviceDiscoveryCoordinator Extended")
@MainActor
struct DeviceDiscoveryCoordinatorExtendedTests {

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
            networkProfileManager: NetworkProfileManager()
        )
    }

    // MARK: - Scan Pipeline Trigger

    @Test func startScanSetsIsScanningTrue() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        coordinator.startScan()
        #expect(coordinator.isScanning == true)
        coordinator.stopScan()
    }

    @Test func stopScanClearsIsScanningFlag() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        coordinator.startScan()
        coordinator.stopScan()
        #expect(coordinator.isScanning == false)
    }

    @Test func doubleStartScanDoesNotResetScanProgress() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        coordinator.startScan()
        let progressAfterFirst = coordinator.scanProgress
        coordinator.startScan() // second call is a no-op while scanning
        #expect(coordinator.scanProgress == progressAfterFirst)
        coordinator.stopScan()
    }

    // MARK: - Multi-Source Device Merge

    @Test func mergeDeduplicatesDevicesWithSameMAC() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        // Insert same MAC twice with different IPs
        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.168.1.5", macAddress: "AA:BB:CC:DD:EE:05", hostname: nil),
        ], profileID: nil)
        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.168.1.6", macAddress: "AA:BB:CC:DD:EE:05", hostname: "updated-host"),
        ], profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        // Same MAC → only one record; IP updated to latest
        let matching = devices.filter { $0.macAddress == "AA:BB:CC:DD:EE:05" }
        #expect(matching.count == 1)
        #expect(matching[0].ipAddress == "192.168.1.6")
        #expect(matching[0].hostname == "updated-host")
    }

    @Test func mergeInsertsNewDevicesWithEmptyMAC() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.168.1.20", macAddress: "", hostname: "device-a"),
            LocalDiscoveredDevice(ipAddress: "192.168.1.21", macAddress: "", hostname: "device-b"),
        ], profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 2)
        let ips = Set(devices.map(\.ipAddress))
        #expect(ips.contains("192.168.1.20"))
        #expect(ips.contains("192.168.1.21"))
    }

    // MARK: - Scan Cancellation

    @Test func scanCancellationSetsIsScanningFalse() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        coordinator.startScan()
        #expect(coordinator.isScanning == true)
        coordinator.stopScan()
        #expect(coordinator.isScanning == false)
    }

    // MARK: - Empty Results

    @Test func mergeEmptyDiscoveredDevicesLeavesStoreUnchanged() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        coordinator.mergeDiscoveredDevices([], profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.isEmpty)
        #expect(coordinator.discoveredDevices.isEmpty)
    }

    @Test func markOfflineWithAllCurrentIPsKeepsDevicesOnline() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "10.0.0.1", macAddress: "00:00:00:00:00:01", hostname: nil),
            LocalDiscoveredDevice(ipAddress: "10.0.0.2", macAddress: "00:00:00:00:00:02", hostname: nil),
        ], profileID: nil)

        // All IPs are still present → nothing should go offline
        coordinator.markOfflineDevices(currentIPs: Set(["10.0.0.1", "10.0.0.2"]), profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.allSatisfy { $0.status == .online })
    }

    @Test func discoveredDevicesIsEmptyBeforeAnyMerge() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)
        #expect(coordinator.discoveredDevices.isEmpty)
    }
}
