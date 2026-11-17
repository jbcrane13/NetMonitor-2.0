import Foundation
import NetMonitorCore
import Testing
@preconcurrency import UserNotifications
@testable import NetMonitor_macOS

@MainActor
private final class RecordingPoster: NotificationRequestPosting {
    private(set) var requests: [UNNotificationRequest] = []
    func post(_ request: UNNotificationRequest) { requests.append(request) }
}

private func makeDefaults() -> (UserDefaults, String) {
    let suite = "AlertRulesMacTests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: suite) ?? .standard, suite)
}

@Suite("AlertRuleStore (#394)")
@MainActor
struct AlertRuleStoreTests {
    @Test func rulesPersistAcrossInstances() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        var rule = AlertRule(name: "Printer offline", trigger: .wentOffline, conditions: AlertRuleConditions(deviceType: .printer))
        store.add(rule)
        rule.isEnabled = false
        store.update(rule)

        #expect(AlertRuleStore(defaults: defaults).rules == [rule])

        store.delete(id: rule.id)
        #expect(AlertRuleStore(defaults: defaults).rules.isEmpty)
    }

    @Test func reloadPicksUpAnotherInstancesChanges() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let appStore = AlertRuleStore(defaults: defaults)
        AlertRuleStore(defaults: defaults).add(AlertRule(name: "new", trigger: .firstSeen))
        #expect(appStore.rules.isEmpty)
        appStore.reload()
        #expect(appStore.rules.map(\.name) == ["new"])
    }
}

@Suite("MacRuleAlerts (#394)")
@MainActor
struct MacRuleAlertsTests {
    private struct Fixture {
        let alerts: MacRuleAlerts
        let poster: RecordingPoster
        let defaults: UserDefaults
        let suite: String
    }

    private func makeFixture(_ rules: [AlertRule]) -> Fixture {
        let (defaults, suite) = makeDefaults()
        let store = AlertRuleStore(defaults: defaults)
        rules.forEach(store.add)
        let poster = RecordingPoster()
        let service = NotificationService(poster: poster, defaults: defaults)
        return Fixture(alerts: MacRuleAlerts(store: store, service: service, defaults: defaults), poster: poster, defaults: defaults, suite: suite)
    }

    private func printerRow() -> LocalDevice {
        LocalDevice(ipAddress: "10.0.0.40", macAddress: "AA:BB:CC:00:00:40", hostname: "printer.local", vendor: "Brother", deviceType: .printer)
    }

    @Test func printerGoesOfflineFiresTheRule() {
        let home = UUID()
        let fixture = makeFixture([AlertRule(
            name: "Printer offline",
            trigger: .wentOffline,
            conditions: AlertRuleConditions(deviceType: .printer, maker: "brother", networkID: home)
        )])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let known = KnownDevice(
            macAddress: "AA:BB:CC:00:00:40", ipAddress: "10.0.0.40", name: "printer.local",
            firstSeen: Date(), lastSeen: Date()
        )

        fixture.alerts.handle(deviceChanges: [.wentOffline(known)], devices: [printerRow()], networkID: home)

        #expect(fixture.poster.requests.map(\.content.title) == ["Printer offline"])
        #expect(fixture.poster.requests.first?.content.body == "printer.local went offline")
        #expect(fixture.poster.requests.first?.content.categoryIdentifier == NotificationService.ruleMatchCategory)
    }

    @Test func conditionsThatDontMatchSendNothing() {
        let fixture = makeFixture([AlertRule(name: "Router offline", trigger: .wentOffline, conditions: AlertRuleConditions(deviceType: .router))])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let known = KnownDevice(macAddress: "AA:BB:CC:00:00:40", ipAddress: "10.0.0.40", name: nil, firstSeen: Date(), lastSeen: Date())

        fixture.alerts.handle(deviceChanges: [.wentOffline(known)], devices: [printerRow()], networkID: nil)

        #expect(fixture.poster.requests.isEmpty)
    }

    @Test func firstSeenAndCameOnlineFromScanEvents() {
        let fixture = makeFixture([
            AlertRule(name: "New device", trigger: .firstSeen),
            AlertRule(name: "Back", trigger: .cameOnline)
        ])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let tv = DeviceObservation(ipAddress: "10.0.0.9", macAddress: nil, name: "tv")
        let printer = DeviceObservation(ipAddress: "10.0.0.40", macAddress: "AA:BB:CC:00:00:40", name: nil)

        fixture.alerts.handle(deviceChanges: [.firstSeen(tv), .cameOnline(printer)], devices: [printerRow()], networkID: nil)

        #expect(fixture.poster.requests.map(\.content.body) == ["tv joined the network for the first time", "printer.local came online"])
    }

    @Test func monitoredTargetLatencyFiresOnCrossingAndTargetDownFiresOnce() {
        let fixture = makeFixture([
            AlertRule(name: "Slow DNS", trigger: .latencyAbove(milliseconds: 100), conditions: AlertRuleConditions(device: "8.8.8.8")),
            AlertRule(name: "DNS down", trigger: .wentOffline, conditions: AlertRuleConditions(device: "Google DNS"))
        ])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        func result(_ reachable: Bool, _ latency: Double?, down: Bool = false, up: Bool = false) -> TargetCheckOutcome {
            TargetCheckOutcome(name: "Google DNS", host: "8.8.8.8", isReachable: reachable, latency: latency, wentDown: down, cameUp: up)
        }

        fixture.alerts.handle(targetResult: result(true, 40))
        fixture.alerts.handle(targetResult: result(true, 150))
        fixture.alerts.handle(targetResult: result(true, 160))
        fixture.alerts.handle(targetResult: result(false, nil, down: true))
        fixture.alerts.handle(targetResult: result(false, nil))

        #expect(fixture.poster.requests.map(\.content.title) == ["Slow DNS", "DNS down"])
    }

    @Test func enableNotificationsOffSilencesRules() {
        let fixture = makeFixture([AlertRule(name: "New device", trigger: .firstSeen)])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.defaults.set(false, forKey: MacAlertNotifier.notificationsEnabledKey)

        fixture.alerts.handle(deviceChanges: [.firstSeen(DeviceObservation(ipAddress: "10.0.0.9", macAddress: nil, name: nil))], devices: [], networkID: nil)

        #expect(fixture.poster.requests.isEmpty)
    }

    @Test func ruleSummaryReadsPlainly() {
        let rule = AlertRule(name: "x", trigger: .latencyAbove(milliseconds: 250), conditions: AlertRuleConditions(device: "nas", maker: "Synology"))
        #expect(RuleDescription.summary(rule, networks: []) == "Latency above 250 ms · device nas · maker contains Synology")
    }
}
