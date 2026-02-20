import Foundation
import SwiftData
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

@Suite("DeviceDiscoveryCoordinator")
@MainActor
struct DeviceDiscoveryCoordinatorTests {

    @Test func mergeDiscoveredDevicesUpdatesExistingRecordByMACAndInsertsNewDevice() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let existing = LocalDevice(
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: nil
        )
        existing.status = .offline
        context.insert(existing)
        try context.save()

        let coordinator = makeCoordinator(context: context)
        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(
                ipAddress: "192.168.1.11",
                macAddress: "aa:bb:cc:dd:ee:ff",
                hostname: "printer.local"
            ),
            LocalDiscoveredDevice(
                ipAddress: "192.168.1.20",
                macAddress: "",
                hostname: "camera.local"
            )
        ])

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 2)

        let updated = devices.first { $0.macAddress == "AA:BB:CC:DD:EE:FF" }
        #expect(updated?.ipAddress == "192.168.1.11")
        #expect(updated?.hostname == "printer.local")
        #expect(updated?.status == .online)

        let inserted = devices.first { $0.ipAddress == "192.168.1.20" }
        #expect(inserted != nil)
        #expect(inserted?.hostname == "camera.local")
    }

    @Test func markOfflineDevicesMarksOnlyMissingIPsOffline() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let onlineDevice = LocalDevice(ipAddress: "192.168.1.2", macAddress: "00:00:00:00:00:02")
        let disappearingDevice = LocalDevice(ipAddress: "192.168.1.3", macAddress: "00:00:00:00:00:03")
        onlineDevice.status = .online
        disappearingDevice.status = .online

        context.insert(onlineDevice)
        context.insert(disappearingDevice)
        try context.save()

        let coordinator = makeCoordinator(context: context)
        coordinator.markOfflineDevices(currentIPs: Set(["192.168.1.2"]))

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        let stillOnline = devices.first { $0.ipAddress == "192.168.1.2" }
        let nowOffline = devices.first { $0.ipAddress == "192.168.1.3" }

        #expect(stillOnline?.status == .online)
        #expect(nowOffline?.status == .offline)
    }

    private func makeCoordinator(context: ModelContext) -> DeviceDiscoveryCoordinator {
        DeviceDiscoveryCoordinator(
            modelContext: context,
            arpScanner: ARPScannerService(timeout: 0.05),
            bonjourScanner: BonjourDiscoveryService()
        )
    }

    private func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }
}
