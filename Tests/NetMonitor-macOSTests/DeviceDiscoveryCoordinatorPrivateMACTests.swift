import Testing
import Foundation
import SwiftData
import NetMonitorCore
import NetworkScanKit
@testable import NetMonitor_macOS

/// A rotated private MAC must update the device's existing row, not add a second one (#411).
@MainActor
struct PrivateMACMergeTests {

    // "02:…" and "0A:…" have the locally administered bit set (private); "AC:…" doesn't.
    private let oldPrivateMAC = "02:11:22:33:44:55"
    private let newPrivateMAC = "0A:66:77:88:99:AA"

    private func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }

    private func makeCoordinator(context: ModelContext) -> DeviceDiscoveryCoordinator {
        DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(),
            pipelineFactory: { _ in ScanPipeline(steps: []) }
        )
    }

    @Test func rotatedPrivateMACReusesRowWithSameIPAndName() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(LocalDevice(ipAddress: "192.0.2.20", macAddress: oldPrivateMAC, hostname: "pixel.local"))
        try context.save()

        makeCoordinator(context: context).mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.20", macAddress: newPrivateMAC, hostname: "pixel.local")
        ], profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 1)
        #expect(devices.first?.macAddress == newPrivateMAC)
        #expect(devices.first?.status == .online)
    }

    @Test func rotatedPrivateMACWithoutNameCreatesNewRow() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(LocalDevice(ipAddress: "192.0.2.20", macAddress: oldPrivateMAC, hostname: "pixel.local"))
        try context.save()

        makeCoordinator(context: context).mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.20", macAddress: newPrivateMAC, hostname: nil)
        ], profileID: nil)

        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 2)
    }

    @Test func ambiguousCandidatesAreNotReused() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(LocalDevice(ipAddress: "192.0.2.20", macAddress: oldPrivateMAC, hostname: "pixel.local"))
        context.insert(LocalDevice(ipAddress: "192.0.2.20", macAddress: "06:00:00:00:00:01", hostname: "pixel.local"))
        try context.save()

        makeCoordinator(context: context).mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.20", macAddress: newPrivateMAC, hostname: "pixel.local")
        ], profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 3)
        #expect(devices.contains { $0.macAddress == oldPrivateMAC })
    }

    @Test func rowSeenUnderItsOwnMACThisScanIsNotReused() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(LocalDevice(ipAddress: "192.0.2.20", macAddress: oldPrivateMAC, hostname: "pixel.local"))
        try context.save()

        // The old device still answers this scan, so the new private MAC is a different device.
        makeCoordinator(context: context).mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.20", macAddress: newPrivateMAC, hostname: "pixel.local"),
            LocalDiscoveredDevice(ipAddress: "192.0.2.20", macAddress: oldPrivateMAC, hostname: "pixel.local")
        ], profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 2)
        #expect(Set(devices.map(\.macAddress)) == [oldPrivateMAC, newPrivateMAC])
    }

    @Test func publicMACWithSameIPAndNameStillCreatesNewRow() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(LocalDevice(ipAddress: "192.0.2.20", macAddress: "AC:DE:48:00:11:22", hostname: "nas.local"))
        try context.save()

        makeCoordinator(context: context).mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.20", macAddress: "AC:DE:48:00:11:33", hostname: "nas.local")
        ], profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 2)
        #expect(devices.contains { $0.macAddress == "AC:DE:48:00:11:22" })
    }
}
