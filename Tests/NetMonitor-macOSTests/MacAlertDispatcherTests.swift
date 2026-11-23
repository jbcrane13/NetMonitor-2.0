import Foundation
import NetMonitorCore
import SwiftData
import Testing
@preconcurrency import UserNotifications
@testable import NetMonitor_macOS

@MainActor
private final class RecordingPoster: NotificationRequestPosting {
    private(set) var requests: [UNNotificationRequest] = []
    var categories: [String] { requests.map(\.content.categoryIdentifier) }
    func post(_ request: UNNotificationRequest) { requests.append(request) }
}

@MainActor
private struct Fixture {
    let dispatcher: MacAlertDispatcher
    let poster: RecordingPoster
    let store: AlertRuleStore
    let defaults: UserDefaults
    let suite: String
    let targetID = UUID()

    init() {
        suite = "MacAlertDispatcherTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite) ?? .standard
        poster = RecordingPoster()
        store = AlertRuleStore(defaults: defaults)
        dispatcher = MacAlertDispatcher(
            service: NotificationService(poster: poster, defaults: defaults),
            store: store,
            defaults: defaults
        )
    }

    func cleanUp() { defaults.removePersistentDomain(forName: suite) }

    func outcome(reachable: Bool = true, latency: Double? = 40, down: Bool = false, up: Bool = false) -> TargetCheckOutcome {
        TargetCheckOutcome(
            targetID: targetID, name: "Router", host: "192.0.2.1",
            isReachable: reachable, latency: latency, wentDown: down, cameUp: up
        )
    }

    var newDevice: DeviceChangeEvent {
        .firstSeen(DeviceObservation(ipAddress: "192.0.2.9", macAddress: nil, name: "tv"))
    }
}

@Suite("MacAlertDispatcher (#486)")
@MainActor
struct MacAlertDispatcherTests {
    @Test func targetDownPostsATargetDownAlert() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }

        fixture.dispatcher.targetWentDown(name: "Router", host: "192.0.2.1")

        #expect(fixture.poster.categories == [NotificationService.targetDownCategory])
    }

    @Test func recoveryPostsARecoveredAlert() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }

        fixture.dispatcher.targetChecked(fixture.outcome(up: true))

        #expect(fixture.poster.categories == [NotificationService.targetRecoveredCategory])
    }

    @Test func latencyAlertsOncePerCrossing() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(100.0, forKey: MacAlertNotifier.latencyThresholdKey)

        fixture.dispatcher.targetChecked(fixture.outcome(latency: 150))
        fixture.dispatcher.targetChecked(fixture.outcome(latency: 160))
        #expect(fixture.poster.categories == [NotificationService.highLatencyCategory])

        fixture.dispatcher.targetChecked(fixture.outcome(latency: 40))
        fixture.dispatcher.targetChecked(fixture.outcome(latency: 170))
        #expect(fixture.poster.categories == [NotificationService.highLatencyCategory, NotificationService.highLatencyCategory])
    }

    @Test func newDeviceCarriesItsNetworkID() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let home = UUID()

        fixture.dispatcher.devicesChanged([fixture.newDevice], devices: [], networkID: home)

        #expect(fixture.poster.categories == [NotificationService.newDeviceCategory])
        #expect(fixture.poster.requests.first?.content.userInfo["networkID"] as? String == home.uuidString)
        #expect(fixture.poster.requests.first?.content.userInfo["ipAddress"] as? String == "192.0.2.9")
    }

    @Test func aMatchingRuleFiresAlongsideTheBuiltInAlert() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.store.add(AlertRule(name: "Any new device", trigger: .firstSeen))

        fixture.dispatcher.devicesChanged([fixture.newDevice], devices: [], networkID: nil)

        #expect(fixture.poster.categories == [NotificationService.newDeviceCategory, NotificationService.ruleMatchCategory])
        #expect(fixture.poster.requests.last?.content.title == "Any new device")
    }

    @Test func aRuleMatchesTargetChecks() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.store.add(AlertRule(name: "Router down", trigger: .wentOffline, conditions: AlertRuleConditions(device: "Router")))

        fixture.dispatcher.targetChecked(fixture.outcome(reachable: false, latency: nil, down: true))

        #expect(fixture.poster.requests.map(\.content.title) == ["Router down"])
    }

    @Test func theNotificationsSwitchSilencesEveryAlert() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(false, forKey: MacAlertNotifier.notificationsEnabledKey)
        fixture.defaults.set(100.0, forKey: MacAlertNotifier.latencyThresholdKey)
        fixture.store.add(AlertRule(name: "Any new device", trigger: .firstSeen))
        fixture.store.add(AlertRule(name: "Router down", trigger: .wentOffline, conditions: AlertRuleConditions(device: "Router")))

        fixture.dispatcher.targetWentDown(name: "Router", host: "192.0.2.1")
        fixture.dispatcher.targetChecked(fixture.outcome(up: true))
        fixture.dispatcher.targetChecked(fixture.outcome(latency: 500))
        fixture.dispatcher.targetChecked(fixture.outcome(reachable: false, latency: nil, down: true))
        fixture.dispatcher.devicesChanged([fixture.newDevice], devices: [], networkID: UUID())

        #expect(fixture.poster.requests.isEmpty)
    }

    @Test func attachInstallsTheCallbacks() throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let schema = Schema([NetworkTarget.self, TargetMeasurement.self, SessionRecord.self, LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let session = MonitoringSession(modelContext: context)
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager()
        )
        defer { withExtendedLifetime(container) {} }
        #expect(session.onTargetDown == nil)
        #expect(coordinator.onDeviceChanges == nil)

        fixture.dispatcher.attach(to: session, discovery: coordinator)
        session.onTargetDown?("Router", "192.0.2.1")
        session.onTargetResult?(fixture.outcome(up: true))
        coordinator.onDeviceChanges?([fixture.newDevice])

        #expect(fixture.poster.categories == [
            NotificationService.targetDownCategory,
            NotificationService.targetRecoveredCategory,
            NotificationService.newDeviceCategory
        ])
        #expect(fixture.poster.requests.last?.content.userInfo["networkID"] as? String == coordinator.networkProfile?.id.uuidString)
    }

    @Test func attachMigratesTheLegacyTargetDownToggle() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(false, forKey: MacAlertNotifier.legacyTargetDownKey)

        fixture.dispatcher.attach(to: nil, discovery: nil)
        fixture.dispatcher.targetWentDown(name: "Router", host: "192.0.2.1")

        #expect(fixture.poster.requests.isEmpty)
    }
}

// MARK: - Model-worded alert text (#453)

/// Answers each request with its first key point, which is always grounded, and records it.
private final class EchoInsightService: InsightServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var received: [InsightRequest] = []
    let isAvailable: Bool

    init(isAvailable: Bool = true) {
        self.isAvailable = isAvailable
    }

    var requests: [InsightRequest] { lock.withLock { received } }

    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        lock.withLock { received.append(request) }
        return AsyncStream { continuation in
            continuation.yield(.finished("Model: " + (request.observations.first ?? "")))
            continuation.finish()
        }
    }
}

@Suite("Mac alert text from the on-device model (#453)")
@MainActor
struct MacAlertTextTests {
    let suite = "MacAlertTextTests.\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suite) ?? .standard }

    private func makeNotifier(_ insight: EchoInsightService, scanning: Bool = false) -> (MacAlertNotifier, RecordingPoster) {
        let poster = RecordingPoster()
        let writer = NotificationTextWriter(service: insight) { scanning }
        return (MacAlertNotifier(service: NotificationService(poster: poster, defaults: defaults), defaults: defaults, writer: writer), poster)
    }

    func until(_ condition: () -> Bool) async {
        for _ in 0 ..< 2000 where !condition() {
            await Task.yield()
        }
    }

    @Test func targetDownGetsModelBodyUnderTheFixedTitle() async {
        defer { defaults.removePersistentDomain(forName: suite) }
        let (notifier, poster) = makeNotifier(EchoInsightService())

        notifier.targetWentDown(name: "Router", host: "192.0.2.1")
        await until { !poster.requests.isEmpty }

        let content = poster.requests.first?.content
        #expect(content?.title == "Target Down")
        #expect(content?.subtitle == NotificationService.generatedSubtitle)
        #expect(content?.body == "Model: Router (192.0.2.1) is not responding.")
    }

    @Test func unavailableModelKeepsFixedText() async {
        defer { defaults.removePersistentDomain(forName: suite) }
        let insight = EchoInsightService(isAvailable: false)
        let (notifier, poster) = makeNotifier(insight)

        notifier.targetWentDown(name: "Router", host: "192.0.2.1")
        await until { !poster.requests.isEmpty }

        #expect(poster.requests.first?.content.body == "Router (192.0.2.1) is not responding")
        #expect(poster.requests.first?.content.subtitle.isEmpty == true)
        #expect(insight.requests.isEmpty)
    }

    @Test func midScanEventsKeepFixedText() async {
        defer { defaults.removePersistentDomain(forName: suite) }
        let insight = EchoInsightService()
        let (notifier, poster) = makeNotifier(insight, scanning: true)

        notifier.targetWentDown(name: "Router", host: "192.0.2.1")
        await until { !poster.requests.isEmpty }

        #expect(poster.requests.first?.content.body == "Router (192.0.2.1) is not responding")
        #expect(insight.requests.isEmpty)
    }

    @Test func newDeviceFactsComeFromTheNetworksRow() async {
        defer { defaults.removePersistentDomain(forName: suite) }
        let insight = EchoInsightService()
        let (notifier, poster) = makeNotifier(insight)
        let row = LocalDevice(ipAddress: "192.0.2.9", macAddress: "AA:BB:CC:DD:EE:FF", hostname: "tv-1234", vendor: "Samsung", deviceType: .tv)
        row.customName = "Living Room TV"

        notifier.devicesChanged(
            [.firstSeen(DeviceObservation(ipAddress: "192.0.2.9", macAddress: "aa:bb:cc:dd:ee:ff", name: "tv-1234"))],
            devices: [row]
        )
        await until { !poster.requests.isEmpty }

        let facts = insight.requests.first?.facts ?? []
        #expect(facts.contains("Device name: Living Room TV"))
        #expect(facts.contains("Maker: Samsung"))
        #expect(facts.contains("Device type: TV"))
        #expect(facts.contains("IP address: 192.0.2.9"))
        #expect(poster.requests.first?.content.body == "Model: Living Room TV joined the network for the first time.")
        #expect(poster.requests.first?.content.title == "New Device Detected")
    }

    @Test func aBurstOfNewDevicesWordsOnlyTheFirstThree() async {
        defer { defaults.removePersistentDomain(forName: suite) }
        let insight = EchoInsightService()
        let (notifier, poster) = makeNotifier(insight)
        let events = (1 ... 5).map { DeviceChangeEvent.firstSeen(DeviceObservation(ipAddress: "192.0.2.\($0)", macAddress: nil, name: "dev\($0)")) }

        notifier.devicesChanged(events)
        await until { poster.requests.count == 5 }

        #expect(insight.requests.count == NotificationTextWriter.burstLimit)
        #expect(poster.requests.map(\.content.subtitle) == [
            NotificationService.generatedSubtitle, NotificationService.generatedSubtitle, NotificationService.generatedSubtitle, "", ""
        ])
        #expect(poster.requests[3].content.body == "dev4 (192.0.2.4) joined the network")
    }

    @Test func disabledAlertNeverAsksTheModel() async {
        defer { defaults.removePersistentDomain(forName: suite) }
        let insight = EchoInsightService()
        let (notifier, poster) = makeNotifier(insight)
        defaults.set(false, forKey: NotificationService.targetDownAlertKey)
        defaults.set(false, forKey: NotificationService.newDeviceAlertKey)

        notifier.targetWentDown(name: "Router", host: "192.0.2.1")
        notifier.devicesChanged([.firstSeen(DeviceObservation(ipAddress: "192.0.2.9", macAddress: nil, name: "tv"))])
        for _ in 0 ..< 100 { await Task.yield() }

        #expect(poster.requests.isEmpty)
        #expect(insight.requests.isEmpty)
    }
}
