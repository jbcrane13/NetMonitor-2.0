import Foundation
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitorCore

/// #619 verification: the user's own grouping actions report a device's presence like a scan
/// does. An offline device grouped into an online one comes back online once, so its Timeline
/// "Device Left" gets its "Back Online" and its rule outage ends; a later outage alerts again.
@Suite("Manual grouping reports presence", .serialized)
@MainActor
final class ManualGroupingEventTests {
    let home = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    nonisolated let suiteName = "ManualGroupingEventTests.\(UUID().uuidString)"
    let container: ModelContainer
    let dispatcher = DeviceEventDispatcher()
    var delivered: [DeviceEvent] = []
    var evaluator = AlertRuleEvaluator()
    var alerts: [AlertRuleEvaluator.Match] = []
    let wired = "00:1B:A9:00:00:10", wifi = "00:1B:A9:00:00:40"

    init() throws {
        container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        dispatcher.subscribe { [weak self] batch in self?.received(batch) }
    }

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    /// Every delivered event, and the alerts an offline and an online rule on the device give.
    func received(_ batch: DeviceEventBatch) {
        delivered += batch.events
        let events = batch.events.compactMap { event -> AlertRuleEvent? in
            var subject = AlertRuleSubject(name: event.name, ipAddress: event.ipAddress, deviceID: event.rowID)
            if event.memberIDs.count > 1 {
                subject.deviceGroupID = event.deviceID
                subject.groupMemberIDs = event.memberIDs
            }
            switch event.kind {
            case .wentOffline: return AlertRuleEvent(kind: .wentOffline, subject: subject)
            case .cameOnline: return AlertRuleEvent(kind: .cameOnline, subject: subject)
            default: return nil
            }
        }
        alerts += evaluator.evaluate(events, rules: rules)
    }

    var rules: [AlertRule] {
        [AlertRule(name: "Studio offline", trigger: .wentOffline, conditions: AlertRuleConditions())]
    }

    func time(_ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    func reconcile(_ scan: [DiscoveredDevice], at minutes: Double) throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        _ = try ScanReconciler(context: ModelContext(container), history: ScanHistory(defaults: defaults), dispatcher: dispatcher)
            .reconcile(scan, networkProfileID: home, scanDate: time(minutes), now: time(minutes))
    }

    func seen(_ ip: String, name: String, mac: String) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: name, vendor: nil, macAddress: mac, latency: 3, discoveredAt: start, source: .local,
            networkProfileID: home
        )
    }

    var router: DiscoveredDevice { seen("10.0.0.1", name: "router", mac: "00:1B:A9:00:00:01") }
    var studio: DiscoveredDevice { seen("10.0.0.10", name: "studio", mac: wired) }
    var studioWifi: DiscoveredDevice { seen("10.0.0.40", name: "studio-wifi", mac: wifi) }

    func row(_ ip: String) throws -> LocalDevice {
        try #require(try ModelContext(container).fetch(FetchDescriptor<LocalDevice>()).first { $0.ipAddress == ip })
    }

    var writer: DeviceGroupWriter { DeviceGroupWriter(container: container, dispatcher: dispatcher) }

    /// Studio's wired interface leaves under grace (one "Device Left" and one alert) while its
    /// Wi-Fi interface, still a separate device, keeps answering.
    func wiredLeaves() throws {
        try reconcile([router], at: 0)
        try reconcile([router, studio, studioWifi], at: 5)
        for minutes in [25.0, 45, 65] {
            try reconcile([router, studioWifi], at: minutes)
        }
        #expect(delivered.map(\.kind).filter { $0 != .joined } == [.wentOffline(since: time(5))])
        #expect(alerts.map(\.event.subject.ipAddress) == ["10.0.0.10"])
    }

    func names(_ kind: DeviceEvent.Kind) -> [String] {
        delivered.filter { $0.kind == kind }.map(\.name)
    }

    @Test("Same device as… joins an offline device to an online one: Back Online once, then the group's outage alerts")
    func manualUnionComesBackOnline() throws {
        try wiredLeaves()
        let undo = try writer.groupForUser([row("10.0.0.40").id, row("10.0.0.10").id], primary: row("10.0.0.40").id)
        #expect(delivered.filter { $0.kind == .cameOnline }.count == 1, "the wired interface's outage ends, once")
        _ = undo
        // The next scan sees the union already: nothing more.
        try reconcile([router, studioWifi], at: 70)
        #expect(delivered.filter { $0.kind == .cameOnline }.count == 1)
        // The whole device leaves: its outage alerts.
        for minutes in [90.0, 110, 130] {
            try reconcile([router], at: minutes)
        }
        #expect(delivered.last?.kind == .wentOffline(since: time(70)))
        #expect(alerts.count == 2, "the group's outage isn't hidden by the wired interface's old one")
    }

    @Test("Undo of that grouping is no event; the wired interface's next outage alerts again")
    func undoIsQuietAndOutagesStillAlert() throws {
        try wiredLeaves()
        let undo = try writer.groupForUser([row("10.0.0.40").id, row("10.0.0.10").id], primary: row("10.0.0.40").id)
        let count = delivered.count
        try writer.undo(undo)
        #expect(delivered.count == count, "the wired row keeps its saved offline presence")
        // It answers again, then leaves again: Back Online, then a second alert.
        try reconcile([router, studio, studioWifi], at: 70)
        #expect(names(.cameOnline).last == "studio")
        for minutes in [90.0, 110, 130] {
            try reconcile([router, studioWifi], at: minutes)
        }
        #expect(alerts.map(\.event.subject.ipAddress) == ["10.0.0.10", "10.0.0.10"])
    }

    @Test("Not the same device on a group whose outage alerted: no event; the separated row's next outage alerts")
    func separatingKeepsPresenceAndOutagesAlert() throws {
        try reconcile([router], at: 0)
        try reconcile([router, studio, studioWifi], at: 5)
        _ = try writer.groupForUser([row("10.0.0.10").id, row("10.0.0.40").id], primary: row("10.0.0.10").id)
        for minutes in [25.0, 45, 65] {
            try reconcile([router], at: minutes)
        }
        #expect(alerts.count == 1, "the group's outage")
        let count = delivered.count
        _ = try writer.ungroupForUser(row("10.0.0.40").id)
        #expect(delivered.count == count, "both rows stay offline: no event")
        // The separated Wi-Fi row answers (its own Back Online ends the group's outage), then leaves.
        try reconcile([router, studioWifi], at: 70)
        for minutes in [90.0, 110, 130] {
            try reconcile([router], at: minutes)
        }
        #expect(alerts.map(\.event.subject.ipAddress) == ["10.0.0.10", "10.0.0.40"])
    }
}
