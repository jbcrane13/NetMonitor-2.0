import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_iOS

// MARK: - Helpers

@MainActor
private func makeContext() throws -> (ModelContainer, ModelContext) {
    let config = ModelConfiguration(UUID().uuidString, schema: Schema([LocalDevice.self]), isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: LocalDevice.self, configurations: config)
    return (container, container.mainContext)
}

private let networkA = UUID()
private let networkB = UUID()

private func scanned(_ ip: String, mac: String?, hostname: String? = nil, network: UUID? = networkA) -> DiscoveredDevice {
    DiscoveredDevice(
        ipAddress: ip, hostname: hostname, vendor: nil, macAddress: mac,
        latency: 5, discoveredAt: Date(), source: .local, networkProfileID: network
    )
}

// MARK: - SavedDeviceLookup

@Suite("SavedDeviceLookup")
@MainActor
struct SavedDeviceLookupTests {
    @Test func findsTheRowOnTheDevicesNetworkByMAC() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        let row = LocalDevice(ipAddress: "192.0.2.99", macAddress: "00:1B:A9:00:00:20", customName: "Office Printer", networkProfileID: networkA)
        context.insert(row)
        // The same MAC on another network is a different saved device.
        context.insert(LocalDevice(ipAddress: "192.0.2.20", macAddress: "00:1B:A9:00:00:20", customName: "Elsewhere", networkProfileID: networkB))
        try context.save()

        let found = SavedDeviceLookup(context: context).snapshot(networkProfileID: networkA).row(for: scanned("192.0.2.20", mac: "00:1b:a9:00:00:20"))

        #expect(found?.id == row.id)
        #expect(found?.displayName == "Office Printer")
    }

    @Test func fallsBackToTheIPWithoutAMAC() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        let row = LocalDevice(ipAddress: "192.0.2.30", macAddress: "", customName: "NAS", networkProfileID: networkA)
        context.insert(row)
        try context.save()

        let found = SavedDeviceLookup(context: context).snapshot(networkProfileID: networkA).row(for: scanned("192.0.2.30", mac: nil))

        #expect(found?.id == row.id)
    }

    @Test func matchesTheUITestFixturesPrivateMAC() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        let row = LocalDevice(
            ipAddress: "192.168.1.10", macAddress: "AA:BB:CC:DD:EE:00", customName: "UITest Office Printer", networkProfileID: networkA
        )
        context.insert(row)
        try context.save()

        let found = SavedDeviceLookup(context: context).row(
            for: scanned("192.168.1.10", mac: "AA:BB:CC:DD:EE:00", hostname: "uitest-device-0"), networkProfileID: networkA
        )

        #expect(found?.id == row.id)
    }

    @Test func ignoresOtherNetworksAndNeverInsertsOrChangesRows() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        let other = LocalDevice(ipAddress: "192.0.2.40", macAddress: "00:1B:A9:00:00:40", customName: "Other", networkProfileID: networkB)
        context.insert(other)
        try context.save()

        let found = SavedDeviceLookup(context: context).snapshot(networkProfileID: networkA).row(for: scanned("192.0.2.41", mac: "00:1B:A9:00:00:40"))

        #expect(found == nil)
        let rows = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(rows.count == 1)
        #expect(rows.first?.ipAddress == "192.0.2.40")
    }

    /// A row saved with no network matches only by an identical MAC: an IP means nothing across networks.
    @Test func aRowWithNoNetworkNeverMatchesByIPAlone() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        context.insert(LocalDevice(ipAddress: "192.0.2.60", macAddress: "00:1B:A9:00:00:60", customName: "Other MAC"))
        context.insert(LocalDevice(ipAddress: "192.0.2.61", macAddress: "", customName: "No MAC"))
        try context.save()
        let saved = SavedDeviceLookup(context: context).snapshot(networkProfileID: networkA)

        #expect(saved.row(for: scanned("192.0.2.60", mac: "00:1B:A9:00:00:99")) == nil)
        #expect(saved.row(for: scanned("192.0.2.61", mac: nil)) == nil)
        #expect(saved.row(for: scanned("192.0.2.61", mac: "00:1B:A9:00:00:61")) == nil)
    }

    /// Rows saved before devices carried a network have none; device detail falls back to them too.
    @Test func fallsBackToRowsWithNoNetwork() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        let legacy = LocalDevice(ipAddress: "192.0.2.50", macAddress: "00:1B:A9:00:00:50", customName: "Old Name")
        context.insert(legacy)
        try context.save()

        let found = SavedDeviceLookup(context: context).snapshot(networkProfileID: networkA).row(for: scanned("192.0.2.50", mac: "00:1B:A9:00:00:50"))

        #expect(found?.id == legacy.id)
    }
}

// MARK: - EventListenerService with the fake discovery service

@Suite("EventListenerService network and device IDs", .serialized)
@MainActor
struct EventListenerNetworkIDTests {
    private final class DeviceBox {
        var devices: [DiscoveredDevice] = []
    }

    @Test func aFakeScanLogsJoinedAndScanCompleteWithTheNetworkID() async throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        let events = SpyNetworkEventService()
        let fake = UITestFakeDiscoveryService()
        let listener = EventListenerService(
            eventService: events,
            discoveryService: fake,
            currentNetworkProfileID: { UITestBootstrap.networkProfileID },
            savedDevices: SavedDeviceLookup(context: context)
        )
        listener.start()
        defer { listener.stop() }

        await fake.scanNetwork(profile: nil)

        await waitUntil({ events.events(ofType: .scanComplete).count == 1 }, timeout: .seconds(5))
        #expect(events.events(ofType: .scanComplete).count == 1)
        #expect(events.events(ofType: .deviceJoined).count == fake.discoveredDevices.count)
        #expect(events.events(ofType: .scanComplete).first?.title == "Scan Complete — 5 devices found")
        #expect(events.loggedEvents.allSatisfy { $0.networkProfileID == UITestBootstrap.networkProfileID })
    }

    @Test func aRenamedDevicesCustomNameAndIDAppearInItsJoinedAndLeftEvents() async throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        let row = LocalDevice(ipAddress: "192.0.2.20", macAddress: "00:1B:A9:00:00:20", hostname: "printer.local", networkProfileID: networkA)
        row.customName = "Office Printer"
        context.insert(row)
        try context.save()
        let box = DeviceBox()
        box.devices = [
            scanned("192.0.2.20", mac: "00:1B:A9:00:00:20", hostname: "printer.local"),
            scanned("192.0.2.21", mac: "00:1B:A9:00:00:21", hostname: "nas.local")
        ]
        let fake = UITestFakeDiscoveryService(devices: { box.devices }, hold: .milliseconds(20))
        let events = SpyNetworkEventService()
        let listener = EventListenerService(
            eventService: events,
            discoveryService: fake,
            currentNetworkProfileID: { networkB },
            savedDevices: SavedDeviceLookup(context: context)
        )
        listener.start()
        defer { listener.stop() }

        await fake.scanNetwork(profile: nil)
        await waitUntil({ events.events(ofType: .scanComplete).count == 1 }, timeout: .seconds(5))
        #expect(events.events(ofType: .scanComplete).count == 1)
        box.devices.removeFirst()
        await fake.scanNetwork(profile: nil)
        await waitUntil({ events.events(ofType: .scanComplete).count == 2 }, timeout: .seconds(5))
        #expect(events.events(ofType: .scanComplete).count == 2)

        let joined = try #require(events.events(ofType: .deviceJoined).first { $0.deviceID == row.id })
        #expect(joined.title == "Device Joined: Office Printer")
        #expect(joined.details == "192.0.2.20")
        #expect(joined.networkProfileID == networkA, "A device's own network wins over the current one")
        let unmatched = try #require(events.events(ofType: .deviceJoined).first { $0.deviceID == nil })
        #expect(unmatched.title == "Device Joined: nas.local")
        let left = try #require(events.events(ofType: .deviceLeft).first)
        #expect(left.title == "Device Left: Office Printer")
        #expect(left.deviceID == row.id)
        #expect(left.networkProfileID == networkA)
    }

    /// A scan already running when the listener starts still logs when it finishes.
    @Test func aScanRunningWhenTheListenerStartsIsLogged() async throws {
        let events = SpyNetworkEventService()
        let fake = UITestFakeDiscoveryService(hold: .milliseconds(200))
        let scan = Task { await fake.scanNetwork(profile: nil) }
        await waitUntil({ fake.isScanning }, timeout: .seconds(5))
        #expect(fake.isScanning)
        let listener = EventListenerService(eventService: events, discoveryService: fake, currentNetworkProfileID: { networkA })
        listener.start()
        defer { listener.stop() }

        await scan.value

        await waitUntil({ events.events(ofType: .scanComplete).count == 1 }, timeout: .seconds(5))
        #expect(events.events(ofType: .scanComplete).count == 1)
    }

    @Test func theFakeServiceHoldsIsScanningThenPublishesStampedDevices() async {
        let fake = UITestFakeDiscoveryService(hold: .milliseconds(100))
        let scan = Task { await fake.scanNetwork(profile: nil) }

        await waitUntil({ fake.isScanning }, timeout: .seconds(5))
        #expect(fake.isScanning)
        #expect(fake.discoveredDevices.isEmpty)
        await scan.value

        #expect(!fake.isScanning)
        #expect(fake.discoveredDevices.count == 5)
        #expect(fake.discoveredDevices.allSatisfy { $0.networkProfileID == UITestBootstrap.networkProfileID })
        #expect(fake.lastScanDate != nil)
    }
}

// MARK: - UI-test range events

@Suite("UITestBootstrap range events")
@MainActor
struct UITestRangeEventsTests {
    @Test func seedsTodayAndTenDaysAgoOnlyWithTheFlagAndOnlyOnce() {
        let events = SpyNetworkEventService()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        UITestBootstrap.seedRangeEventsIfNeeded(into: events, arguments: ["--uitesting"], now: now)
        #expect(events.loggedEvents.isEmpty)

        UITestBootstrap.seedRangeEventsIfNeeded(into: events, arguments: ["--uitesting", "--seed-test-events"], now: now)
        UITestBootstrap.seedRangeEventsIfNeeded(into: events, arguments: ["--uitesting", "--seed-test-events"], now: now)

        #expect(events.loggedEvents.map(\.title) == ["UITest Event 10 Days Ago", "UITest Event Today"])
        #expect(events.loggedEvents.map(\.timestamp) == [now.addingTimeInterval(-10 * 86400), now.addingTimeInterval(-60)])
        #expect(events.loggedEvents.allSatisfy { $0.networkProfileID == UITestBootstrap.networkProfileID })
    }
}
