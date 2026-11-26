import Foundation
import SwiftData
import NetMonitorCore
import Testing
@testable import NetMonitor_macOS

// MARK: - Helpers

/// A clock and scheduler the test moves by hand, so the flap window never sleeps.
@MainActor
private final class ManualClock {
    private(set) var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var pending: [(due: Date, action: @MainActor () -> Void)] = []

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        pending.append((now.addingTimeInterval(delay), action))
    }

    /// Moves time forward, running every scheduled action that falls due on the way, in order.
    func advance(by interval: TimeInterval) {
        let end = now.addingTimeInterval(interval)
        while let next = pending.enumerated().filter({ $0.element.due <= end }).min(by: { $0.element.due < $1.element.due }) {
            pending.remove(at: next.offset)
            now = next.element.due
            next.element.action()
        }
        now = end
    }
}

@MainActor
private func makeRecorder() -> (MacEventRecorder, NetworkEventService, ManualClock) {
    let events = NetworkEventService()
    let clock = ManualClock()
    let recorder = MacEventRecorder(
        eventService: events,
        now: { clock.now },
        schedule: { delay, action in clock.schedule(after: delay, action) },
        gatewayOf: { $0.gatewayIP }
    )
    return (recorder, events, clock)
}

private let profileID = UUID()
private let printerObservation = DeviceObservation(ipAddress: "192.0.2.20", macAddress: "00:1B:A9:00:00:20", name: "printer.local")
private let printerKnown = KnownDevice(
    macAddress: "00:1B:A9:00:00:20", ipAddress: "192.0.2.20", name: "printer.local",
    firstSeen: Date(timeIntervalSince1970: 0), lastSeen: Date(timeIntervalSince1970: 0)
)

/// Oldest first, which is easier to read than the log's newest-first order.
private func titles(_ events: NetworkEventService) -> [String] {
    events.events.reversed().map(\.title)
}

private func profile(id: UUID = profileID, gateway: String) -> NetworkProfile {
    NetworkProfile(
        id: id,
        interfaceName: "en0",
        ipAddress: "192.0.2.10",
        network: NetworkUtilities.IPv4Network(
            networkAddress: 0xC000_0200, broadcastAddress: 0xC000_02FF, interfaceAddress: 0xC000_020A, netmask: 0xFFFF_FF00
        ),
        connectionType: .wifi,
        name: "Test",
        gatewayIP: gateway,
        subnet: "192.0.2.0/24",
        isLocal: true,
        discoveryMethod: .auto
    )
}

// MARK: - Device events

@Suite("MacEventRecorder devices")
@MainActor
struct MacEventRecorderDeviceTests {
    @Test func firstSeenIsLoggedAsJoinedWithTheRowsDisplayNameAndIDs() throws {
        let (recorder, events, _) = makeRecorder()
        let row = LocalDevice(ipAddress: "192.0.2.20", macAddress: "00:1B:A9:00:00:20", hostname: "printer.local", networkProfileID: profileID)
        row.customName = "Office Printer"

        recorder.devicesChanged([.firstSeen(printerObservation)], devices: [row], profileID: profileID)

        let event = try #require(events.events.first)
        #expect(events.events.count == 1)
        #expect(event.type == .deviceJoined)
        #expect(event.title == "Device Joined: Office Printer")
        #expect(event.details == "192.0.2.20")
        #expect(event.deviceID == row.id)
        #expect(event.networkProfileID == profileID)
    }

    @Test func anUnmatchedDeviceKeepsItsOwnNameAndHasNoDeviceID() throws {
        let (recorder, events, _) = makeRecorder()

        recorder.devicesChanged([.firstSeen(printerObservation)], devices: [], profileID: profileID)

        let event = try #require(events.events.first)
        #expect(event.title == "Device Joined: printer.local")
        #expect(event.deviceID == nil)
        #expect(event.networkProfileID == profileID)
    }

    @Test func wentOfflineIsLoggedAsLeftAndCameOnlineAsBackOnline() {
        let (recorder, events, clock) = makeRecorder()

        recorder.devicesChanged([.wentOffline(printerKnown)], devices: [], profileID: profileID)
        clock.advance(by: 11 * 60)
        recorder.devicesChanged([.cameOnline(printerObservation)], devices: [], profileID: profileID)

        #expect(events.events.map(\.type) == [.deviceJoined, .deviceLeft])
        #expect(titles(events) == ["Device Left: printer.local", "Device Back Online: printer.local"])
    }

    @Test func changedIsNotLogged() {
        let (recorder, events, _) = makeRecorder()

        recorder.devicesChanged([.changed(printerObservation, previous: printerKnown)], devices: [], profileID: profileID)

        #expect(events.events.isEmpty)
    }
}

// MARK: - Flap guard

@Suite("MacEventRecorder flap guard")
@MainActor
struct MacEventRecorderFlapTests {
    @Test func threeFlapsInTenMinutesLogOneLeftAndOneJoined() {
        let (recorder, events, clock) = makeRecorder()
        for _ in 0..<3 {
            recorder.devicesChanged([.wentOffline(printerKnown)], devices: [], profileID: profileID)
            clock.advance(by: 60)
            recorder.devicesChanged([.cameOnline(printerObservation)], devices: [], profileID: profileID)
            clock.advance(by: 60)
        }
        // The window ends with the device online, which is what was last written: no correction.
        clock.advance(by: 20 * 60)

        #expect(titles(events) == ["Device Left: printer.local", "Device Back Online: printer.local"])
    }

    @Test func leftJoinedLeftEndsWithATrailingLeftWhenTheWindowCloses() throws {
        let (recorder, events, clock) = makeRecorder()
        recorder.devicesChanged([.wentOffline(printerKnown)], devices: [], profileID: profileID)
        clock.advance(by: 60)
        recorder.devicesChanged([.cameOnline(printerObservation)], devices: [], profileID: profileID)
        clock.advance(by: 60)
        recorder.devicesChanged([.wentOffline(printerKnown)], devices: [], profileID: profileID)
        #expect(events.events.count == 2, "The second left inside the window is dropped")

        clock.advance(by: 10 * 60)

        #expect(titles(events) == ["Device Left: printer.local", "Device Back Online: printer.local", "Device Left: printer.local"])
        let trailing = try #require(events.events.first)
        // Written when the window closed, stamped with when the device was last seen leaving.
        #expect(trailing.timestamp == Date(timeIntervalSince1970: 1_800_000_000 + 120))
        #expect(trailing.networkProfileID == profileID)
    }

    @Test func eventsAreWrittenAtOnceWithTheirRealTime() throws {
        let (recorder, events, clock) = makeRecorder()
        clock.advance(by: 42)

        recorder.devicesChanged([.wentOffline(printerKnown)], devices: [], profileID: profileID)

        #expect(try #require(events.events.first).timestamp == Date(timeIntervalSince1970: 1_800_000_042))
    }

    @Test func theTrailingWriteOpensANewWindow() {
        let (recorder, events, clock) = makeRecorder()
        recorder.devicesChanged([.wentOffline(printerKnown)], devices: [], profileID: profileID)
        recorder.devicesChanged([.cameOnline(printerObservation)], devices: [], profileID: profileID)
        recorder.devicesChanged([.wentOffline(printerKnown)], devices: [], profileID: profileID)
        clock.advance(by: 10 * 60) // trailing left
        clock.advance(by: 60)

        // A left right after the trailing left stays inside the new window's limit.
        recorder.devicesChanged([.cameOnline(printerObservation)], devices: [], profileID: profileID)
        recorder.devicesChanged([.wentOffline(printerKnown)], devices: [], profileID: profileID)

        #expect(events.events.map(\.type) == [.deviceJoined, .deviceLeft, .deviceJoined, .deviceLeft])
    }

    /// The row can be in one scan's rows and missing from the next; the MAC keeps one window.
    @Test func aDeviceKeepsOneWindowWhetherOrNotItsRowIsFound() {
        let (recorder, events, _) = makeRecorder()
        let row = LocalDevice(ipAddress: "192.0.2.20", macAddress: "00:1B:A9:00:00:20", hostname: "printer.local", networkProfileID: profileID)

        recorder.devicesChanged([.firstSeen(printerObservation)], devices: [row], profileID: profileID)
        recorder.devicesChanged([.wentOffline(printerKnown)], devices: [], profileID: profileID)
        recorder.devicesChanged([.cameOnline(printerObservation)], devices: [], profileID: profileID)

        #expect(events.events.map(\.type) == [.deviceLeft, .deviceJoined])
    }

    @Test func eachDeviceHasItsOwnWindow() {
        let (recorder, events, _) = makeRecorder()
        let other = KnownDevice(
            macAddress: "00:1B:A9:00:00:21", ipAddress: "192.0.2.21", name: "nas.local", firstSeen: .distantPast, lastSeen: .distantPast
        )

        recorder.devicesChanged([.wentOffline(printerKnown), .wentOffline(other)], devices: [], profileID: profileID)

        #expect(events.events.count == 2)
    }
}

// MARK: - Scan, connectivity, gateway

@Suite("MacEventRecorder network")
@MainActor
struct MacEventRecorderNetworkTests {
    @Test func scanCompleteMatchesTheIOSTitle() throws {
        let (recorder, events, _) = makeRecorder()

        recorder.scanCompleted(profileID: profileID, deviceCount: 2)
        recorder.scanCompleted(profileID: profileID, deviceCount: 1)

        #expect(titles(events) == ["Scan Complete — 2 devices found", "Scan Complete — 1 device found"])
        #expect(events.events.allSatisfy { $0.type == .scanComplete && $0.networkProfileID == profileID })
    }

    @Test func connectivityTransitionsAreLogged() {
        let (recorder, events, _) = makeRecorder()

        recorder.connectivityChanged(isOnline: false, profileID: profileID, at: Date(timeIntervalSince1970: 1))
        recorder.connectivityChanged(isOnline: true, profileID: profileID, at: Date(timeIntervalSince1970: 2))

        #expect(titles(events) == ["Network Disconnected", "Network Connected"])
        #expect(events.events.map(\.severity) == [.success, .warning])
        #expect(events.events.allSatisfy { $0.type == .connectivityChange && $0.networkProfileID == profileID })
        #expect(events.events.map(\.timestamp) == [Date(timeIntervalSince1970: 2), Date(timeIntervalSince1970: 1)])
    }

    @Test func aNewGatewayOnTheSameNetworkIsLogged() throws {
        let (recorder, events, _) = makeRecorder()

        recorder.localNetworkObserved(profile(gateway: "192.0.2.1"))
        recorder.localNetworkObserved(profile(gateway: "192.0.2.254"))

        let event = try #require(events.events.first)
        #expect(events.events.count == 1)
        #expect(event.type == .gatewayChange)
        #expect(event.title == "Gateway Changed: 192.0.2.254")
        #expect(event.details == "Was 192.0.2.1")
        #expect(event.networkProfileID == profileID)
    }

    @Test func theFirstNetworkAndNetworkSwitchesLogNoGatewayChange() {
        let (recorder, events, _) = makeRecorder()
        let other = UUID()

        recorder.localNetworkObserved(profile(gateway: "192.0.2.1"))
        recorder.localNetworkObserved(profile(id: other, gateway: "198.51.100.1"))
        recorder.localNetworkObserved(profile(gateway: "192.0.2.254"))
        recorder.localNetworkObserved(profile(gateway: "192.0.2.254"))
        recorder.localNetworkObserved(nil)

        #expect(events.events.isEmpty)
    }
}

// MARK: - App-scope connectivity monitor

/// Path updates the test sends by hand, one stream per monitor in creation order.
private final class FakePaths: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncStream<Bool>.Continuation] = []

    var made: Int { lock.withLock { continuations.count } }

    func make() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        lock.withLock { continuations.append(continuation) }
        return stream
    }

    func send(_ satisfied: Bool, toMonitor index: Int) {
        let continuation = lock.withLock { continuations[index] }
        continuation.yield(satisfied)
    }
}

@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@Suite("AppConnectivityMonitor", .serialized)
@MainActor
struct AppConnectivityMonitorTests {
    private let networkA = UUID()
    private let networkB = UUID()

    private struct Harness {
        let host: AppConnectivityMonitor
        let paths: FakePaths
        let clock: ManualClock
        let events: NetworkEventService
        let container: ModelContainer
        let current: CurrentNetwork

        @MainActor
        func records() throws -> [ConnectivityRecord] {
            try container.mainContext.fetch(FetchDescriptor<ConnectivityRecord>(sortBy: [SortDescriptor(\.timestamp)]))
        }
    }

    /// The network the Mac is on, which the debounced network-change check hasn't caught up with yet.
    @MainActor
    private final class CurrentNetwork {
        var id: UUID?
    }

    private func makeHarness() throws -> Harness {
        let config = ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: ConnectivityRecord.self, configurations: config)
        let (recorder, events, clock) = makeRecorder()
        let paths = FakePaths()
        let current = CurrentNetwork()
        current.id = networkA
        let host = AppConnectivityMonitor(
            modelContext: container.mainContext,
            pathEvents: { paths.make() },
            now: { clock.now },
            schedule: { delay, action in clock.schedule(after: delay, action) },
            isCurrent: { $0 == current.id },
            onTransition: { isOnline, id, timestamp in recorder.connectivityChanged(isOnline: isOnline, profileID: id, at: timestamp) }
        )
        return Harness(host: host, paths: paths, clock: clock, events: events, container: container, current: current)
    }

    @Test func aReconnectionOnTheSameNetworkIsRecordedWithItsOwnTimeAfterSettling() async throws {
        let harness = try makeHarness()
        defer { harness.host.stop() }
        harness.host.run(for: profile(id: networkA, gateway: "192.0.2.1"))
        #expect(await eventually { harness.paths.made == 1 })

        harness.paths.send(false, toMonitor: 0)
        #expect(await eventually { harness.events.events.count == 1 })
        let reconnectedAt = harness.clock.now
        harness.paths.send(true, toMonitor: 0)
        #expect(await eventually { harness.host.monitor?.isOnline == true })
        #expect(harness.events.events.count == 1, "Not recorded until it settles")
        harness.clock.advance(by: ConnectivityMonitor.onlineSettleDelay)

        #expect(titles(harness.events) == ["Network Disconnected", "Network Connected"])
        #expect(harness.events.events.first?.timestamp == reconnectedAt)
        #expect(try harness.records().map(\.isOnline) == [false, true])
        #expect(try harness.records().allSatisfy { $0.profileID == networkA })
    }

    /// Wi-Fi drops on network A and comes back on B: the path recovers before the app's debounced
    /// network-change check replaces A's monitor.
    @Test func aReconnectionToAnotherNetworkIsRecordedUnderTheNewNetworkOnly() async throws {
        let harness = try makeHarness()
        defer { harness.host.stop() }
        harness.host.run(for: profile(id: networkA, gateway: "192.0.2.1"))
        #expect(await eventually { harness.paths.made == 1 })
        harness.paths.send(false, toMonitor: 0)
        #expect(await eventually { harness.events.events.count == 1 })

        harness.current.id = networkB
        harness.paths.send(true, toMonitor: 0)
        #expect(await eventually { harness.host.monitor?.isOnline == true })
        harness.clock.advance(by: ConnectivityMonitor.onlineSettleDelay)
        harness.host.run(for: profile(id: networkB, gateway: "198.51.100.1"))
        #expect(await eventually { harness.paths.made == 2 })
        harness.paths.send(true, toMonitor: 1)
        #expect(await eventually { harness.events.events.count == 2 })

        #expect(titles(harness.events) == ["Network Disconnected", "Network Connected"])
        #expect(harness.events.events.reversed().map(\.networkProfileID) == [networkA, networkB])
        let records = try harness.records()
        #expect(records.map(\.isOnline) == [false, true])
        #expect(records.map(\.profileID) == [networkA, networkB])
    }

    @Test func aSeamlessSwitchRecordsAConnectionUnderTheNewNetwork() async throws {
        let harness = try makeHarness()
        defer { harness.host.stop() }
        harness.host.run(for: profile(id: networkA, gateway: "192.0.2.1"))
        #expect(await eventually { harness.paths.made == 1 })

        harness.current.id = networkB
        harness.host.run(for: profile(id: networkB, gateway: "198.51.100.1"))
        #expect(await eventually { harness.paths.made == 2 })
        harness.paths.send(true, toMonitor: 1)

        #expect(await eventually { harness.events.events.count == 1 })
        #expect(titles(harness.events) == ["Network Connected"])
        #expect(harness.events.events.first?.networkProfileID == networkB)
    }

    @Test func aNewGatewayOnTheSameNetworkKeepsTheStateAndRecordsNoConnection() async throws {
        let harness = try makeHarness()
        defer { harness.host.stop() }
        harness.host.run(for: profile(id: networkA, gateway: "192.0.2.1"))
        let first = try #require(harness.host.monitor)
        #expect(await eventually { harness.paths.made == 1 })
        // A dashboard appearing or disappearing doesn't touch it; the same network keeps it.
        harness.host.run(for: profile(id: networkA, gateway: "192.0.2.1"))
        #expect(harness.host.monitor === first)

        harness.host.run(for: profile(id: networkA, gateway: "192.0.2.254"))
        #expect(harness.host.monitor !== first)
        #expect(await eventually { harness.paths.made == 2 })
        harness.paths.send(true, toMonitor: 1)
        harness.paths.send(false, toMonitor: 1)

        #expect(await eventually { harness.events.events.count == 1 })
        #expect(titles(harness.events) == ["Network Disconnected"])
    }

    @Test func stoppingBeforeTheMonitorStartsOpensNoPathMonitor() async throws {
        let harness = try makeHarness()
        harness.host.run(for: profile(id: networkA, gateway: "192.0.2.1"))
        harness.host.stop()
        try await Task.sleep(for: .milliseconds(100))

        #expect(harness.paths.made == 0)
        #expect(harness.host.monitor == nil)
    }
}

// MARK: - UI-test scan fixture

@Suite("UITestScanFixture", .serialized)
@MainActor
struct UITestScanFixtureTests {
    /// The `--uitesting --seed-test-device` path end to end: the real seed and its baseline scan,
    /// the fixture pipeline and the recorder. The seeded row is the baseline, so only the printer
    /// joins (#603: the reconcile's event, named by the printer's row).
    @Test func aScanFromAnEmptyTrackerPlusTheSeedReportsOnlyThePrinterAndLogsIt() async throws {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let suite = "UITestScanFixtureTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profiles = NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: { [profile(gateway: "192.0.2.1")] })
        let networkID = try #require(profiles.activeProfile?.id)

        UITestScanFixture.seedDevice(into: context, profileID: networkID)
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: profiles,
            pipelineFactory: UITestScanFixture.pipelineFactory,
            portChecker: { _, _, _ in false },
            scanHistory: .forTesting(),
            dispatcher: DeviceEventDispatcher()
        )
        defer { coordinator.stopScan() }
        UITestScanFixture.recordBaseline(in: coordinator, profileID: networkID)
        let events = NetworkEventService()
        let recorder = MacEventRecorder(eventService: events)
        recorder.attach(to: coordinator)
        recorder.attach(to: coordinator) // a second attach must not log everything twice
        var firstSeen: [String] = []
        coordinator.addDeviceChangeHandler { changes, _ in
            for case let .firstSeen(device) in changes {
                firstSeen.append(device.ipAddress)
            }
        }

        coordinator.startScan()
        let deadline = ContinuousClock.now + .seconds(10)
        while coordinator.isScanning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(firstSeen == [UITestScanFixture.printerIP])
        #expect(titles(events) == ["Device Joined: uitest-printer", "Scan Complete — 2 devices found"])
        #expect(events.events.allSatisfy { $0.networkProfileID == networkID })
        let printerRow = try #require(coordinator.discoveredDevices.first { $0.ipAddress == UITestScanFixture.printerIP })
        #expect(events.events.last?.deviceID == printerRow.id)
    }

    /// The default route's gateway can change without a network change; a scan re-reads it.
    @Test func aScanOfTheLocalNetworkLogsAGatewayChange() async throws {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        defer { withExtendedLifetime(container) {} }
        let suite = "UITestScanFixtureTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profiles = NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: { [profile(gateway: "192.0.2.1")] })
        let local = try #require(profiles.localProfile)
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: container.mainContext,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: profiles,
            pipelineFactory: UITestScanFixture.pipelineFactory,
            portChecker: { _, _, _ in false },
            scanHistory: .forTesting(),
            dispatcher: DeviceEventDispatcher()
        )
        defer { coordinator.stopScan() }
        let events = NetworkEventService()
        var routedGateway = "192.0.2.1"
        let recorder = MacEventRecorder(eventService: events, gatewayOf: { _ in routedGateway })
        recorder.attach(to: coordinator)
        recorder.localNetworkObserved(local)

        routedGateway = "192.0.2.254"
        coordinator.startScan()
        let deadline = ContinuousClock.now + .seconds(10)
        while coordinator.isScanning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        let gatewayEvents = events.events(ofType: .gatewayChange)
        #expect(gatewayEvents.map(\.title) == ["Gateway Changed: 192.0.2.254"])
        #expect(gatewayEvents.first?.networkProfileID == local.id)
    }

    @Test func seededEventsAreTodayAndTenDaysAgo() {
        let events = NetworkEventService()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        UITestScanFixture.seedEvents(into: events, profileID: profileID, now: now)

        #expect(events.events.map(\.timestamp) == [now.addingTimeInterval(-60), now.addingTimeInterval(-10 * 86400)])
    }
}
