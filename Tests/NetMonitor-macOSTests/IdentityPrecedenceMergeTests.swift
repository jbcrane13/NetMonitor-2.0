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

    /// A device known only by its UPnP name kept that name in `hostname` before SchemaV3; now
    /// it's a friendly name. Private-MAC rotation still has a name to compare.
    @Test("A UPnP-named device with a private MAC keeps its row when the MAC rotates")
    func upnpNamedPrivateMACRotates() throws {
        let (container, context, coordinator) = try makeCoordinator()
        _ = container
        let saved = LocalDevice(ipAddress: "192.168.2.60", macAddress: "AA:BB:CC:00:00:01", hostname: "Living Room TV")
        context.insert(saved) // as 2.2.x saved it: the friendly name in hostname
        try context.save()

        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(
                ipAddress: "192.168.2.60", macAddress: "AA:BB:CC:00:00:02", hostname: nil,
                identity: DeviceIdentity(friendlyName: IdentityValue("Living Room TV", source: .upnp))
            )
        ], profileID: nil)

        let rows = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(rows.count == 1)
        #expect(rows.first?.macAddress == "AA:BB:CC:00:00:02")
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

    /// #439: rows saved before hostname identity, for devices that no longer answer scans.
    @Test("A saved row the scan didn't find gets a guessed maker from its name; a saved maker stays")
    func staleRowIsFilledFromItsName() throws {
        let (container, context, coordinator) = try makeCoordinator()
        _ = container
        context.insert(LocalDevice(ipAddress: "192.168.2.108", macAddress: "", hostname: "wiz_fcd4aa.lan", status: .offline))
        context.insert(LocalDevice(ipAddress: "192.168.2.2", macAddress: "", hostname: "unifi-pro-max-16-switch.lan", status: .offline))
        // An unranked maker from an older build, and a MAC-prefix maker: neither is replaced.
        let legacy = LocalDevice(ipAddress: "192.168.2.154", macAddress: "", hostname: "samsung-microwave.lan", status: .offline)
        legacy.manufacturer = "SmartThings"
        context.insert(legacy)
        context.insert(LocalDevice(
            ipAddress: "192.168.2.30", macAddress: "", hostname: "unifi-pro-max-16-switch", vendor: "Raspberry Pi Trading", status: .offline
        ))
        try context.save()

        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity())], profileID: nil)

        let byIP = try Dictionary(uniqueKeysWithValues: context.fetch(FetchDescriptor<LocalDevice>()).map { ($0.ipAddress, $0) })
        #expect(byIP["192.168.2.108"]?.identity.maker == IdentityValue("WiZ", source: .hostnameGuess))
        #expect(byIP["192.168.2.108"]?.vendor == nil)
        #expect(byIP["192.168.2.2"]?.maker == "Ubiquiti")
        #expect(byIP["192.168.2.2"]?.identity.model == IdentityValue("UniFi Pro Max 16 Switch", source: .hostnameGuess))
        #expect(byIP["192.168.2.154"]?.identity.maker == IdentityValue("SmartThings", source: nil))
        #expect(byIP["192.168.2.30"]?.maker == "Raspberry Pi Trading")
        #expect(byIP["192.168.2.30"]?.modelName == nil)
    }
}
