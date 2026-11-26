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

private func scanned(_ ip: String, mac: String?, hostname: String? = nil, network: UUID? = networkA) -> DiscoveredDevice {
    DiscoveredDevice(
        ipAddress: ip, hostname: hostname, vendor: nil, macAddress: mac,
        latency: 5, discoveredAt: Date(), source: .local, networkProfileID: network
    )
}

// MARK: - EventListenerService

@Suite("EventListenerService network and device IDs", .serialized)
@MainActor
struct EventListenerNetworkIDTests {
    private final class DeviceBox {
        var devices: [DiscoveredDevice] = []
    }

    /// A scan alone logs Scan Complete; device entries come only from the reconciled scan's
    /// device events (#603, `DeviceEventConsumerTests`).
    @Test func aFakeScanLogsScanCompleteWithTheNetworkIDAndNoDeviceEntries() async throws {
        let events = SpyNetworkEventService()
        let fake = UITestFakeDiscoveryService()
        let listener = EventListenerService(
            eventService: events, discoveryService: fake, currentNetworkProfileID: { UITestBootstrap.networkProfileID },
            dispatcher: DeviceEventDispatcher()
        )
        listener.start()
        defer { listener.stop() }

        await fake.scanNetwork(profile: nil)

        await waitUntil({ events.events(ofType: .scanComplete).count == 1 }, timeout: .seconds(5))
        #expect(events.events(ofType: .scanComplete).count == 1)
        #expect(events.events(ofType: .deviceJoined).isEmpty)
        #expect(events.events(ofType: .scanComplete).first?.title == "Scan Complete — 5 devices found")
        #expect(events.loggedEvents.allSatisfy { $0.networkProfileID == UITestBootstrap.networkProfileID })
    }

    @Test func aRenamedDevicesCustomNameAndRowIDAppearInItsEntries() throws {
        let (container, context) = try makeContext()
        let suite = "EventListenerNetworkIDTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let dispatcher = DeviceEventDispatcher()
        let events = SpyNetworkEventService()
        let listener = EventListenerService(eventService: events, discoveryService: MockDeviceDiscoveryService(), dispatcher: dispatcher)
        listener.start()
        defer { listener.stop() }
        let row = LocalDevice(ipAddress: "192.0.2.20", macAddress: "00:1B:A9:00:00:20", hostname: "printer.local", networkProfileID: networkA)
        row.customName = "Office Printer"
        row.status = .offline
        context.insert(row)
        try context.save()
        let reconciler = ScanReconciler(context: ModelContext(container), history: ScanHistory(defaults: defaults), dispatcher: dispatcher)
        let scanTime = Date()
        try reconciler.reconcile(
            [scanned("192.0.2.1", mac: "00:1B:A9:00:00:01", hostname: "router")], networkProfileID: networkA, scanDate: scanTime, now: scanTime
        )
        let later = scanTime.addingTimeInterval(600)
        try reconciler.reconcile(
            [
                scanned("192.0.2.1", mac: "00:1B:A9:00:00:01", hostname: "router"),
                scanned("192.0.2.20", mac: "00:1B:A9:00:00:20", hostname: "printer.local")
            ],
            networkProfileID: networkA, scanDate: later, now: later
        )

        let back = try #require(events.events(ofType: .deviceJoined).first)
        #expect(back.title == "Device Back Online: Office Printer")
        #expect(back.details == "192.0.2.20")
        #expect(back.deviceID == row.id)
        #expect(back.networkProfileID == networkA)
    }

    @Test func anEmptyScanLogsNoDepartures() async throws {
        let box = DeviceBox()
        let fake = UITestFakeDiscoveryService(devices: { box.devices }, hold: .milliseconds(20))
        let events = SpyNetworkEventService()
        let listener = EventListenerService(eventService: events, discoveryService: fake, currentNetworkProfileID: { networkA })
        listener.start()
        defer { listener.stop() }

        box.devices = [scanned("192.0.2.1", mac: "00:1B:A9:00:00:01")]
        await fake.scanNetwork(profile: nil)
        await waitUntil({ events.events(ofType: .scanComplete).count == 1 }, timeout: .seconds(5))
        box.devices = []
        await fake.scanNetwork(profile: nil)
        await waitUntil({ events.events(ofType: .scanComplete).count == 2 }, timeout: .seconds(5))

        #expect(events.events(ofType: .scanComplete).count == 2)
        #expect(events.events(ofType: .deviceLeft).isEmpty)
        #expect(events.events(ofType: .scanComplete).allSatisfy { $0.networkProfileID == networkA })
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

    @Test func theTodayEventIsNeverBeforeMidnight() throws {
        let events = SpyNetworkEventService()
        let midnight = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let now = midnight.addingTimeInterval(30)

        UITestBootstrap.seedRangeEventsIfNeeded(into: events, arguments: ["--uitesting", "--seed-test-events"], now: now)

        let today = try #require(events.loggedEvents.first { $0.title == "UITest Event Today" })
        #expect(today.timestamp == midnight)
    }
}
