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
