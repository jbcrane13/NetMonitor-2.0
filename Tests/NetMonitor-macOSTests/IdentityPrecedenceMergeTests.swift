import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_macOS

/// ADR-022 (#462): a saved device's maker, model and friendly name change only to an equal or
/// higher-ranked value, across scans.
@Suite(.serialized)
@MainActor
struct IdentityPrecedenceMergeTests {

    private func makeCoordinator() throws -> (ModelContainer, ModelContext, DeviceDiscoveryCoordinator) {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: container.mainContext,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(),
            pipelineFactory: { _ in ScanPipeline(steps: []) }
        )
        return (container, container.mainContext, coordinator)
    }

    private func scan(_ identity: DeviceIdentity) -> LocalDiscoveredDevice {
        LocalDiscoveredDevice(ipAddress: "192.168.2.50", macAddress: "", hostname: "living-room.lan", identity: identity)
    }

    private func row(in context: ModelContext) throws -> LocalDevice {
        try #require(try context.fetch(FetchDescriptor<LocalDevice>()).first)
    }

    /// #443: Bonjour is time-boxed, so a later scan may hear only UPnP.
    @Test("A Bonjour model stays when a later scan has only a UPnP model or a guess")
    func bonjourModelStaysAcrossScans() throws {
        let (container, context, coordinator) = try makeCoordinator()
        _ = container
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(model: IdentityValue("AppleTV14,1", source: .bonjour)))], profileID: nil)
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(model: IdentityValue("Apple TV 4K", source: .upnp)))], profileID: nil)
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(model: IdentityValue("Apple TV", source: .hostnameGuess)))], profileID: nil)
        #expect(try row(in: context).identity.model == IdentityValue("AppleTV14,1", source: .bonjour))

        // A newer Bonjour model replaces it: equal rank, newer wins.
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(model: IdentityValue("AppleTV14,2", source: .bonjour)))], profileID: nil)
        #expect(try row(in: context).modelName == "AppleTV14,2")
    }

    @Test("A guess fills an empty maker, and the device's own maker replaces it")
    func guessThenAnnouncement() throws {
        let (container, context, coordinator) = try makeCoordinator()
        _ = container
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(maker: IdentityValue("Meross", source: .hostnameGuess)))], profileID: nil)
        #expect(try row(in: context).maker == "Meross")
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(maker: IdentityValue("Meross Technology", source: .upnp)))], profileID: nil)
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(maker: IdentityValue("Meross", source: .hostnameGuess)))], profileID: nil)
        #expect(try row(in: context).identity.maker == IdentityValue("Meross Technology", source: .upnp))
    }

    @Test("A value saved before sources were stored gives way to any sourced value")
    func unsourcedValueGivesWay() throws {
        let (container, context, coordinator) = try makeCoordinator()
        _ = container
        let saved = LocalDevice(ipAddress: "192.168.2.50", macAddress: "", hostname: "living-room.lan")
        saved.modelName = "Q80"
        context.insert(saved)
        try context.save()
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(model: IdentityValue("TV", source: .hostnameGuess)))], profileID: nil)
        #expect(try row(in: context).identity.model == IdentityValue("TV", source: .hostnameGuess))
    }

    @Test("A UniFi name outranks a UPnP name; neither is written into the hostname")
    func friendlyNames() throws {
        let (container, context, coordinator) = try makeCoordinator()
        _ = container
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(friendlyName: IdentityValue("Blake's TV", source: .unifi)))], profileID: nil)
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(friendlyName: IdentityValue("[TV] Samsung Q80", source: .upnp)))], profileID: nil)
        let device = try row(in: context)
        #expect(device.friendlyName == "Blake's TV")
        #expect(device.hostname == "living-room.lan")
        #expect(device.displayName == "Blake's TV")
    }

    @Test("Device name: custom name, else friendly name, else hostname, else IP")
    func deviceNameOrder() {
        let device = LocalDevice(ipAddress: "192.168.2.50", macAddress: "")
        #expect(device.displayName == "192.168.2.50")
        device.hostname = "living-room.lan"
        #expect(device.displayName == "living-room.lan")
        device.resolvedHostname = "tv.lan"
        #expect(device.displayName == "tv.lan")
        device.friendlyName = "Living Room TV"
        #expect(device.displayName == "Living Room TV")
        device.customName = "Big TV"
        #expect(device.displayName == "Big TV")
    }
}
