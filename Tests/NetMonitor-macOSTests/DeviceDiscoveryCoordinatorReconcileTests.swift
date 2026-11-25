import Foundation
import SwiftData
import Testing
@testable import NetMonitor_macOS
import NetMonitorCore
import NetworkScanKit

// MARK: - Test support

/// UserDefaults that never touch disk, for a test's own `ScanHistory` and change tracker (#596).
final class InMemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]

    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values[defaultName] = nil }
}

extension ScanHistory {
    /// A history no other test shares.
    static func forTesting() -> ScanHistory {
        // A suite name is required to init; nothing is written to it.
        ScanHistory(defaults: InMemoryDefaults(suiteName: "nm-tests-unused") ?? InMemoryDefaults())
    }
}

extension LocalDiscoveredDevice {
    /// The engine's form of this observation, which the final merge takes.
    var scanned: DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ipAddress, hostname: hostname, vendor: vendor, macAddress: macAddress.isEmpty ? nil : macAddress,
            latency: latency, discoveredAt: Date(), source: .local, openPorts: openPorts, isCached: isCached, identity: identity
        )
    }
}

extension DeviceDiscoveryCoordinator {
    /// Test shorthand for the final merge of a scan of `devices`.
    @discardableResult
    func reconcileScan(_ devices: [LocalDiscoveredDevice], profileID: UUID?, now: Date? = nil) -> Bool {
        reconcileScan(devices.map(\.scanned), profileID: profileID, now: now)
    }
}

extension DeviceDiscoveryCoordinator {
    /// Test shorthand: scans in which only `answering` answers, until rows that missed are past
    /// the grace policy (3 scans and 15 minutes), so they go offline. Needs one live device.
    func missPastGrace(answering: [LocalDiscoveredDevice], profileID: UUID?, after start: Date = Date()) {
        for minutes in [16.0, 17, 18] {
            reconcileScan(answering, profileID: profileID, now: start.addingTimeInterval(minutes * 60))
        }
    }
}

/// A clock a test steps by hand.
@MainActor
final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(minutes: Double) { now = now.addingTimeInterval(minutes * 60) }
}

// MARK: - Final merge through ScanReconciler (#596)

@Suite("DeviceDiscoveryCoordinator reconcile (#596)", .serialized)
@MainActor
struct DeviceDiscoveryCoordinatorReconcileTests {
    let home = UUID()

    func makeStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }

    func makeCoordinator(
        _ context: ModelContext,
        clock: TestClock,
        pipeline: (@Sendable (ScanPipelineInputs) -> ScanPipeline)? = nil
    ) -> DeviceDiscoveryCoordinator {
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(userDefaults: InMemoryDefaults()),
            pipelineFactory: pipeline ?? { _ in ScanPipeline(steps: []) },
            portChecker: { _, _, _ in false },
            scanHistory: .forTesting(),
            clock: { clock.now }
        )
        coordinator.changeTracker = DeviceChangeTracker(defaults: InMemoryDefaults())
        return coordinator
    }

    static func device(_ ip: String, _ name: String?, mac: String = "", latency: Double? = nil, cached: Bool = false) -> LocalDiscoveredDevice {
        LocalDiscoveredDevice(ipAddress: ip, macAddress: mac, hostname: name, latency: latency, isCached: cached)
    }

    @Test func coordinatorRowsShowWhatTheReconcilerSaved() throws {
        let (container, context) = try makeStore()
        _ = container
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        let coordinator = makeCoordinator(context, clock: clock)
        coordinator.reconcileScan([Self.device("10.0.0.2", "nas", mac: "AA:00:00:00:00:02", latency: 4)], profileID: nil)

        clock.advance(minutes: 1)
        coordinator.reconcileScan([Self.device("10.0.0.3", "nas", mac: "AA:00:00:00:00:02", latency: 6)], profileID: nil)

        let row = try #require(coordinator.discoveredDevices.first)
        #expect(coordinator.discoveredDevices.count == 1)
        #expect(row.ipAddress == "10.0.0.3")
        #expect(row.status == .online)
        #expect(row.lastSeen == clock.now)
        #expect(row.latencyHistory == [4, 6])
    }

    @Test func aMissedDeviceGoesOfflineOnlyAfterThreeScansAndFifteenMinutes() throws {
        let (container, context) = try makeStore()
        _ = container
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        let coordinator = makeCoordinator(context, clock: clock)
        let router = Self.device("10.0.0.1", "router", mac: "AA:00:00:00:00:01")
        let printer = Self.device("10.0.0.20", "printer", mac: "AA:00:00:00:00:20")
        coordinator.reconcileScan([router, printer], profileID: home)

        func printerStatus() -> DeviceStatus? {
            coordinator.discoveredDevices.first { $0.hostname == "printer" }?.status
        }
        // Three quick misses: still within the interval.
        for _ in 1...3 {
            clock.advance(minutes: 1)
            coordinator.reconcileScan([router], profileID: home)
        }
        #expect(printerStatus() == .online)
        // Past 15 minutes, but this is the first scan long enough after it was seen: still 4 misses.
        clock.advance(minutes: 15)
        coordinator.reconcileScan([router], profileID: home)
        #expect(printerStatus() == .offline)
    }

    @Test func aScanInWhichNothingAnsweredChangesNothing() throws {
        let (container, context) = try makeStore()
        _ = container
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        let coordinator = makeCoordinator(context, clock: clock)
        coordinator.reconcileScan([Self.device("10.0.0.1", "router", mac: "AA:00:00:00:00:01")], profileID: home)
        for _ in 1...4 {
            clock.advance(minutes: 10)
            #expect(coordinator.reconcileScan([LocalDiscoveredDevice](), profileID: home) == false)
            #expect(coordinator.reconcileScan([Self.device("10.0.0.1", "router", mac: "AA:00:00:00:00:01", cached: true)], profileID: home) == false)
        }
        #expect(coordinator.discoveredDevices.map(\.status) == [.online])
    }

    /// DHCP reuse on a Mac with no MACs (macOS 27): a different name at a saved device's address
    /// is a new device, through the sparse merge and the final one, and the saved name and notes stay.
    @Test func dhcpReuseWithoutMACsMakesANewRowAndKeepsTheOldOnesNotes() throws {
        let (container, context) = try makeStore()
        _ = container
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        context.insert(LocalDevice(ipAddress: "10.0.0.20", macAddress: "", hostname: "living-room-tv", notes: "Mounted", networkProfileID: home))
        try context.save()
        let coordinator = makeCoordinator(context, clock: clock)

        clock.advance(minutes: 1)
        coordinator.mergeSparseSnapshot([Self.device("10.0.0.20", nil, latency: 3)], profileID: home, now: clock.now)
        coordinator.reconcileScan([Self.device("10.0.0.20", "kitchen-phone", latency: 3)], profileID: home)

        let rows = coordinator.discoveredDevices.sorted { ($0.hostname ?? "") < ($1.hostname ?? "") }
        #expect(rows.map(\.hostname) == ["kitchen-phone", "living-room-tv"])
        #expect(rows[1].notes == "Mounted")
        #expect(rows[0].notes == nil)
    }

    @Test func aNamelessDeviceKeepsItsRowOnlyWithinGrace() throws {
        let (container, context) = try makeStore()
        _ = container
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        let coordinator = makeCoordinator(context, clock: clock)
        coordinator.reconcileScan([Self.device("10.0.0.30", nil)], profileID: home)
        clock.advance(minutes: 10)
        coordinator.reconcileScan([Self.device("10.0.0.30", nil)], profileID: home)
        #expect(coordinator.discoveredDevices.count == 1)

        // Gone longer than the grace window: an address alone no longer proves it's the same device.
        clock.advance(minutes: 30)
        coordinator.reconcileScan([Self.device("10.0.0.30", nil)], profileID: home)
        #expect(coordinator.discoveredDevices.count == 2)
    }

    @Test func theSparseMergeInsertsOnlyDevicesWithAPublicMAC() throws {
        let (container, context) = try makeStore()
        _ = container
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        let coordinator = makeCoordinator(context, clock: clock)
        coordinator.mergeSparseSnapshot(
            [
                Self.device("10.0.0.40", nil),
                Self.device("10.0.0.41", nil, mac: "AC:DE:48:00:00:41"),
                Self.device("10.0.0.42", nil, mac: "AA:00:00:00:00:42")
            ],
            profileID: home, now: clock.now
        )
        #expect(coordinator.discoveredDevices.map(\.ipAddress) == ["10.0.0.41"])
    }

    /// A row saved before the Mac had a network is never adopted by address; unlike the iPhone,
    /// the Mac has no device detail to adopt it, so the scan makes the network's own row.
    @Test func aDeviceAtAnUnassignedRowsAddressGetsItsOwnRowOnTheMac() throws {
        let (container, context) = try makeStore()
        _ = container
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        context.insert(LocalDevice(ipAddress: "10.0.0.50", macAddress: "", hostname: "nas"))
        try context.save()
        let coordinator = makeCoordinator(context, clock: clock)
        coordinator.reconcileScan([Self.device("10.0.0.50", "nas")], profileID: home)
        #expect(coordinator.discoveredDevices.map(\.hostname) == ["nas"])
        #expect(coordinator.discoveredDevices.first?.networkProfileID == home)
    }

    // MARK: Timeline follows grace

    @Test func theTimelineReportsLeftAndCameBackWithTheRows() async throws {
        let (container, context) = try makeStore()
        _ = container
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        let box = FixtureUpsertBox(devices: [
            Self.engine("10.0.0.1", "router", mac: "AA:00:00:00:00:01"), Self.engine("10.0.0.20", "printer", mac: "AA:00:00:00:00:20")
        ])
        let coordinator = makeCoordinator(context, clock: clock) { _ in
            ScanPipeline(steps: [ScanPipeline.Step(phases: [FixtureUpsertScanPhase(box: box)], concurrent: false)])
        }
        var events: [DeviceChangeEvent] = []
        coordinator.addDeviceChangeHandler { changes, _ in events += changes }

        func scan() async {
            coordinator.startScan()
            let deadline = ContinuousClock.now + .seconds(30)
            while coordinator.isScanning, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        func printer() -> LocalDevice? { coordinator.discoveredDevices.first { $0.hostname == "printer" } }

        await scan()
        box.devices = [Self.engine("10.0.0.1", "router", mac: "AA:00:00:00:00:01")]
        for _ in 1...2 {
            clock.advance(minutes: 10)
            await scan()
        }
        #expect(printer()?.status == .online)
        #expect(!events.contains {
            if case .wentOffline = $0 {
                true
            } else {
                false
            }
        })

        clock.advance(minutes: 10)
        await scan()
        #expect(printer()?.status == .offline)
        #expect(events.contains {
            if case .wentOffline(let known) = $0 {
                known.name == "printer"
            } else {
                false
            }
        })

        box.devices.append(Self.engine("10.0.0.20", "printer", mac: "AA:00:00:00:00:20"))
        clock.advance(minutes: 10)
        await scan()
        #expect(printer()?.status == .online)
        #expect(events.contains {
            if case .cameOnline(let seen) = $0 {
                seen.name == "printer"
            } else {
                false
            }
        })
    }

    static func engine(_ ip: String, _ name: String?, mac: String? = nil, cached: Bool = false) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: name, vendor: nil, macAddress: mac, latency: cached ? nil : 5,
            discoveredAt: Date(), source: .local, isCached: cached
        )
    }

    // MARK: Same rows as the iPhone

    /// One fixture of scans fed to the Mac coordinator (sparse merge, then final) and to
    /// `ScanReconciler` as the iPhone's `DeviceRecordUpdater` builds it: the same rows.
    @Test func macAndIPhoneMakeTheSameRowsFromTheSameScans() throws {
        let scans: [[DiscoveredDevice]] = [
            [
                Self.engine("10.0.0.1", "router", mac: "AA:00:00:00:00:01"),
                Self.engine("10.0.0.20", "printer"),
                Self.engine("10.0.0.30", nil),
                Self.engine("10.0.0.40", "stale", mac: "AA:00:00:00:00:40", cached: true),
                Self.engine("10.0.0.60", "nas")
            ],
            [
                Self.engine("10.0.0.1", "router", mac: "AA:00:00:00:00:01"),
                Self.engine("10.0.0.20", "kitchen-phone"),
                Self.engine("10.0.0.31", nil, mac: "02:00:00:00:00:00")
            ],
            [Self.engine("10.0.0.1", "router", mac: "AA:00:00:00:00:01")],
            [
                Self.engine("10.0.0.1", "router", mac: "AA:00:00:00:00:01"),
                Self.engine("10.0.0.20", "printer"),
                // Back 30 minutes later with a readable, public MAC: the same row, never a second one.
                Self.engine("10.0.0.60", "nas", mac: "AC:DE:48:00:00:60")
            ]
        ]
        let start = Date(timeIntervalSince1970: 1_790_000_000)

        let (macContainer, macContext) = try makeStore()
        _ = macContainer
        let clock = TestClock(start)
        let mac = makeCoordinator(macContext, clock: clock)
        for (index, scan) in scans.enumerated() {
            clock.now = start.addingTimeInterval(Double(index) * 600)
            // At the enrichment transition names aren't resolved yet.
            let sparse = DeviceDiscoveryCoordinator.mapDiscoveredDevices(scan).map {
                LocalDiscoveredDevice(ipAddress: $0.ipAddress, macAddress: $0.macAddress, hostname: nil, isCached: $0.isCached)
            }
            mac.mergeSparseSnapshot(sparse, profileID: home, now: clock.now)
            mac.reconcileScan(scan, profileID: home, now: clock.now)
        }

        let (phoneContainer, phoneContext) = try makeStore()
        _ = phoneContainer
        let phone = ScanReconciler(context: ModelContext(phoneContainer), history: .forTesting())
        for (index, scan) in scans.enumerated() {
            let now = start.addingTimeInterval(Double(index) * 600)
            try phone.reconcile(scan, networkProfileID: home, scanDate: now, now: now)
        }

        func rows(_ context: ModelContext) throws -> [String] {
            try context.fetch(FetchDescriptor<LocalDevice>())
                .map { "\($0.ipAddress) \($0.macAddress) \($0.hostname ?? "-") \($0.status.rawValue) \($0.lastSeen.timeIntervalSince(start))" }
                .sorted()
        }
        let macRows = try rows(macContext)
        #expect(try macRows == rows(phoneContext))
        #expect(macRows.count == 6)
    }
}
