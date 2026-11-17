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

    @Test func unreadableStoredRulesAreSetAsideAndTheLastGoodRulesKept() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let good = AlertRule(name: "Printer offline", trigger: .wentOffline)
        store.add(good)
        let garbage = Data("{not json".utf8)
        defaults.set(garbage, forKey: AlertRuleStore.storageKey)

        store.reload()
        #expect(store.rules == [good], "Last good rules kept")
        #expect(store.loadError != nil)
        #expect(defaults.data(forKey: AlertRuleStore.unreadableKey) == garbage, "Raw data kept aside")

        store.add(AlertRule(name: "New", trigger: .firstSeen))
        #expect(defaults.data(forKey: AlertRuleStore.unreadableKey) == garbage, "A save never overwrites the copy set aside")
        #expect(AlertRuleStore(defaults: defaults).rules.map(\.name) == ["Printer offline", "New"])
    }

    @Test func aFreshStoreOnUnreadableDataShowsTheError() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("{not json".utf8), forKey: AlertRuleStore.storageKey)

        let store = AlertRuleStore(defaults: defaults)

        #expect(store.rules.isEmpty)
        #expect(store.loadError != nil)
    }

    @Test func aStaleSecondInstanceDoesNotLoseTheOthersEdits() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let mainWindow = AlertRuleStore(defaults: defaults)
        let settingsScene = AlertRuleStore(defaults: defaults)

        mainWindow.add(AlertRule(name: "first", trigger: .firstSeen))
        settingsScene.add(AlertRule(name: "second", trigger: .wentOffline))

        #expect(AlertRuleStore(defaults: defaults).rules.map(\.name) == ["first", "second"])
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
        let dnsTarget = UUID()
        func result(_ reachable: Bool, _ latency: Double?, down: Bool = false, up: Bool = false) -> TargetCheckOutcome {
            TargetCheckOutcome(
                targetID: dnsTarget, name: "Google DNS", host: "8.8.8.8",
                isReachable: reachable, latency: latency, wentDown: down, cameUp: up
            )
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

        let joined = DeviceObservation(ipAddress: "10.0.0.9", macAddress: nil, name: nil)
        fixture.alerts.handle(deviceChanges: [.firstSeen(joined)], devices: [], networkID: nil)

        #expect(fixture.poster.requests.isEmpty)
    }

    @Test func aMonitoredTargetGetsItsDeviceMetadataFromTheNetworksRows() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let home = UUID()
        let store = AlertRuleStore(defaults: defaults)
        store.add(AlertRule(
            name: "Slow printer",
            trigger: .latencyAbove(milliseconds: 100),
            conditions: AlertRuleConditions(deviceType: .printer, maker: "brother", networkID: home)
        ))
        let poster = RecordingPoster()
        let row = printerRow()
        let alerts = MacRuleAlerts(
            store: store, service: NotificationService(poster: poster, defaults: defaults), defaults: defaults
        ) { ([row], home) }

        alerts.handle(targetResult: TargetCheckOutcome(
            targetID: UUID(), name: "Printer", host: "10.0.0.40",
            isReachable: true, latency: 300, wentDown: false, cameUp: false
        ))

        #expect(poster.requests.map(\.content.title) == ["Slow printer"])
    }

    @Test func twoTargetsOnTheSameHostCrossIndependently() {
        let fixture = makeFixture([AlertRule(name: "Slow", trigger: .latencyAbove(milliseconds: 100))])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let icmp = UUID()
        let https = UUID()
        func check(_ id: UUID, _ latency: Double) {
            fixture.alerts.handle(targetResult: TargetCheckOutcome(
                targetID: id, name: "Router", host: "10.0.0.1",
                isReachable: true, latency: latency, wentDown: false, cameUp: false
            ))
        }

        check(icmp, 150)
        check(https, 40)
        check(icmp, 150)

        #expect(fixture.poster.requests.count == 1, "The HTTPS check didn't re-arm the ICMP target's rule")
    }

    @Test func aMACMatchesItsRowExactlyAndNeverFallsBackToAnotherDevicesIP() {
        let fixture = makeFixture([AlertRule(name: "Printer back", trigger: .cameOnline, conditions: AlertRuleConditions(deviceType: .printer))])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        // The printer row sits at 10.0.0.40. An unknown device with its own MAC now answers at
        // that IP: it must not borrow the printer's type.
        let stranger = DeviceObservation(ipAddress: "10.0.0.40", macAddress: "00:1B:63:99:99:99", name: nil)

        fixture.alerts.handle(deviceChanges: [.cameOnline(stranger)], devices: [printerRow()], networkID: nil)
        #expect(fixture.poster.requests.isEmpty)

        // The printer, by MAC, at a new IP still matches its own row.
        let moved = DeviceObservation(ipAddress: "10.0.0.41", macAddress: "aa:bb:cc:00:00:40", name: nil)
        fixture.alerts.handle(deviceChanges: [.cameOnline(moved)], devices: [printerRow()], networkID: nil)
        #expect(fixture.poster.requests.map(\.content.title) == ["Printer back"])
    }

    @Test func ruleSummaryReadsPlainly() {
        let rule = AlertRule(name: "x", trigger: .latencyAbove(milliseconds: 250), conditions: AlertRuleConditions(device: "nas", maker: "Synology"))
        #expect(RuleDescription.summary(rule, networks: []) == "Latency above 250 ms · device nas · maker contains Synology")
    }
}
