import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@preconcurrency import UserNotifications
@testable import NetMonitor_macOS

/// The Mac's device events end to end (#603, #594 PR2): the coordinator's reconcile, Core's
/// `DeviceEventDispatcher`, then the Timeline recorder and the rule alerts, with what the user
/// would see (the Timeline entry, the notification) asserted.
@Suite("Mac device events come from the reconcile (#603)", .serialized)
@MainActor
struct DeviceEventWiringTests {
    static let primaryIP = "192.168.77.60"
    static let memberIP = "192.168.77.61"
    static let primaryMAC = "02:00:00:77:00:60"
    static let memberMAC = "02:00:00:77:00:61"
    static let name = "Studio Mac"
    static let start = Date(timeIntervalSince1970: 1_790_000_000)

    struct Harness {
        let container: ModelContainer
        let context: ModelContext
        let coordinator: DeviceDiscoveryCoordinator
        let clock: TestClock
        let events: NetworkEventService
        /// Held here: the coordinator's handler holds it weakly.
        let recorder: MacEventRecorder
    }

    func makeContainer() throws -> ModelContainer {
        let schema = Schema([NetworkTarget.self, TargetMeasurement.self, SessionRecord.self, LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A coordinator on `container` with its own dispatcher, history and clock, and a Timeline
    /// recorder attached.
    func makeHarness(_ container: ModelContainer) -> Harness {
        let clock = TestClock(Self.start)
        let context = container.mainContext
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(userDefaults: InMemoryDefaults(), activeProfilesProvider: { [] }),
            pipelineFactory: { _ in ScanPipeline(steps: []) },
            portChecker: { _, _, _ in false },
            scanHistory: .forTesting(),
            clock: { clock.now },
            dispatcher: DeviceEventDispatcher()
        )
        let events = NetworkEventService()
        let recorder = MacEventRecorder(eventService: events, now: { clock.now }, schedule: { _, _ in })
        recorder.attach(to: coordinator)
        return Harness(container: container, context: context, coordinator: coordinator, clock: clock, events: events, recorder: recorder)
    }

    static func scanned(_ ip: String, _ name: String?, mac: String? = nil) -> DiscoveredDevice {
        DiscoveredDevice(ipAddress: ip, hostname: name, vendor: nil, macAddress: mac, latency: 4, discoveredAt: Date(), source: .local)
    }

    /// The Studio Mac on two interfaces, both offline since two hours before `start`, grouped
    /// through the writer; the primary (Ethernet) holds the name.
    func seedGroup(in container: ModelContainer) throws -> (primary: UUID, member: UUID) {
        let setup = ModelContext(container)
        let primary = LocalDevice(ipAddress: Self.primaryIP, macAddress: Self.primaryMAC, hostname: "studio", status: .offline)
        primary.customName = Self.name
        let member = LocalDevice(ipAddress: Self.memberIP, macAddress: Self.memberMAC, hostname: "studio", status: .offline)
        for row in [primary, member] {
            row.lastSeen = Self.start.addingTimeInterval(-2 * 3600)
            row.firstSeen = Self.start.addingTimeInterval(-86400)
            setup.insert(row)
        }
        try setup.save()
        try DeviceGroupWriter(container: container).group([primary.id, member.id], primary: primary.id, source: .user)
        return (primary.id, member.id)
    }

    /// A baseline scan (the network's first recorded one) in which only `other` answers, so the
    /// group's rows stay offline and the next scan's events count.
    func recordBaseline(_ harness: Harness) {
        harness.clock.now = Self.start.addingTimeInterval(-60)
        harness.coordinator.reconcileScan([Self.scanned("192.168.77.2", "router", mac: "02:00:00:77:00:02")], profileID: nil)
        harness.clock.now = Self.start
    }

    func rulePoster(_ rule: AlertRule, _ harness: Harness) throws -> (GroupEventPoster, () -> Void) {
        let suite = "DeviceEventWiringTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = AlertRuleStore(defaults: defaults)
        store.add(rule)
        let poster = GroupEventPoster()
        let dispatcher = MacAlertDispatcher(service: NotificationService(poster: poster, defaults: defaults), store: store, defaults: defaults)
        dispatcher.attach(to: nil, discovery: harness.coordinator)
        return (poster, {
            withExtendedLifetime(dispatcher) {}
            defaults.removePersistentDomain(forName: suite)
        })
    }

    // MARK: - #603 acceptance

    /// DHCP gives a known device's address to another device and no MAC is readable (every
    /// device on macOS 27): the rows split as `PresenceMatch` splits them, so the Timeline shows
    /// the newcomer joining, then the old device leaving after grace, never "changed".
    @Test func dhcpReuseWithoutMACsJoinsTheNewcomerAndTheOldDeviceLeavesAfterGrace() throws {
        let container = try makeContainer()
        let harness = makeHarness(container)
        harness.coordinator.reconcileScan([Self.scanned("10.0.0.5", "kitchen-ipad")], profileID: nil)
        #expect(harness.events.events.isEmpty, "The network's first recorded scan is the baseline")

        harness.clock.advance(minutes: 10)
        harness.coordinator.reconcileScan([Self.scanned("10.0.0.5", "living-tv")], profileID: nil)
        let rows = try ModelContext(container).fetch(FetchDescriptor<LocalDevice>())
        let ipad = try #require(rows.first { $0.hostname == "kitchen-ipad" })
        let tv = try #require(rows.first { $0.hostname == "living-tv" })
        #expect(titles(harness.events) == ["Device Joined: living-tv"])
        #expect(harness.events.events.first?.deviceID == tv.id)

        // Grace: three missed scans and 15 minutes since the iPad last answered.
        for _ in 0..<2 {
            harness.clock.advance(minutes: 10)
            harness.coordinator.reconcileScan([Self.scanned("10.0.0.5", "living-tv")], profileID: nil)
        }
        #expect(titles(harness.events) == ["Device Left: kitchen-ipad", "Device Joined: living-tv"])
        let left = try #require(harness.events.events(ofType: .deviceLeft).first)
        #expect(left.deviceID == ipad.id)
        #expect(left.details == "10.0.0.5")
        #expect(try ModelContext(container).fetch(FetchDescriptor<LocalDevice>()).count == 2, "Two devices, two rows")
    }

    // MARK: - Groups

    /// One interface coming back is the device coming back: the Timeline entry names the device
    /// and keeps its primary row's ID.
    @Test func aGroupComingBackThroughItsSecondInterfaceIsOneEntryNamedByTheDevice() throws {
        let container = try makeContainer()
        let ids = try seedGroup(in: container)
        let harness = makeHarness(container)
        recordBaseline(harness)

        harness.coordinator.reconcileScan([Self.scanned(Self.memberIP, "studio", mac: Self.memberMAC)], profileID: nil)

        #expect(titles(harness.events) == ["Device Back Online: \(Self.name)"])
        #expect(harness.events.events.first?.deviceID == ids.primary)
    }

    /// Both interfaces coming back in one scan is the device coming back: one recovery alert, not
    /// none (an interface check would see the other interface online) and not two.
    @Test func bothInterfacesBackInOneScanAlertOnce() throws {
        let container = try makeContainer()
        let ids = try seedGroup(in: container)
        let harness = makeHarness(container)
        recordBaseline(harness)
        let rule = AlertRule(name: "Studio back", trigger: .cameOnline, conditions: AlertRuleConditions(deviceID: ids.primary))
        let (poster, cleanup) = try rulePoster(rule, harness)
        defer { cleanup() }

        harness.coordinator.reconcileScan([
            Self.scanned(Self.primaryIP, "studio", mac: Self.primaryMAC),
            Self.scanned(Self.memberIP, "studio", mac: Self.memberMAC)
        ], profileID: nil)

        #expect(poster.requests(for: rule).count == 1)
        #expect(poster.requests(for: rule).first?.content.body.contains(Self.name) == true)
        #expect(titles(harness.events) == ["Device Back Online: \(Self.name)"])
    }

    /// One interface going offline while the other answers is not the device going offline (no
    /// event, no alert); the last one going offline is, once.
    @Test func anInterfaceGoingOfflineWhileAnotherAnswersFiresNoDeviceRule() throws {
        let container = try makeContainer()
        let ids = try seedGroup(in: container)
        let harness = makeHarness(container)
        recordBaseline(harness)
        let rule = AlertRule(name: "Studio down", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: ids.primary))
        let (poster, cleanup) = try rulePoster(rule, harness)
        defer { cleanup() }
        let both = [Self.scanned(Self.primaryIP, "studio", mac: Self.primaryMAC), Self.scanned(Self.memberIP, "studio", mac: Self.memberMAC)]
        let router = Self.scanned("192.168.77.2", "router", mac: "02:00:00:77:00:02")
        harness.coordinator.reconcileScan(both, profileID: nil)

        // The Ethernet interface misses scans past grace while Wi-Fi answers.
        for _ in 0..<4 {
            harness.clock.advance(minutes: 10)
            harness.coordinator.reconcileScan([both[1], router], profileID: nil)
        }
        let primaryID = ids.primary
        let primary = try #require(ModelContext(container).fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.id == primaryID })).first)
        #expect(primary.status == .offline)
        #expect(poster.requests(for: rule).isEmpty, "Wi-Fi still answers: the device is online")
        #expect(harness.events.events(ofType: .deviceLeft).isEmpty)

        // Then Wi-Fi goes quiet too, past grace: the device left.
        for _ in 0..<4 {
            harness.clock.advance(minutes: 10)
            harness.coordinator.reconcileScan([router], profileID: nil)
        }
        #expect(poster.requests(for: rule).count == 1)
        #expect(titles(harness.events).filter { $0.hasPrefix("Device Left") } == ["Device Left: \(Self.name)"])
    }
}

@MainActor
final class GroupEventPoster: NotificationRequestPosting {
    private(set) var requests: [UNNotificationRequest] = []
    func post(_ request: UNNotificationRequest) { requests.append(request) }

    func requests(for rule: AlertRule) -> [UNNotificationRequest] {
        requests.filter { $0.identifier.hasPrefix("rule-\(rule.id.uuidString)") }
    }
}

@MainActor
private func titles(_ events: NetworkEventService) -> [String] {
    events.events.map(\.title)
}
