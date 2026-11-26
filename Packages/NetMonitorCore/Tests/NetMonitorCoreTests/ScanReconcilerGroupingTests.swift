import Foundation
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitorCore

/// #594 PR2 and #603: the reconciler groups a device's interfaces on same-scan evidence, in its own
/// save, and reduces the scan to at most one event per device, delivered once.
@Suite("ScanReconciler grouping and device events", .serialized)
@MainActor
final class ScanReconcilerGroupingTests {
    let home = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    nonisolated let suiteName = "ScanReconcilerGroupingTests.\(UUID().uuidString)"
    let container: ModelContainer
    let context: ModelContext
    let dispatcher = DeviceEventDispatcher()
    var delivered: [DeviceEventBatch] = []

    init() throws {
        container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
        dispatcher.subscribe { [weak self] batch in self?.delivered.append(batch) }
    }

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    func minutes(_ value: Double) -> Date {
        start.addingTimeInterval(value * 60)
    }

    @discardableResult
    func reconcile(_ scan: [DiscoveredDevice], at time: Double) throws -> [DeviceEvent] {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let reconciler = ScanReconciler(context: context, history: ScanHistory(defaults: defaults), dispatcher: dispatcher)
        guard case let .applied(_, _, events) = try reconciler.reconcile(
            scan, networkProfileID: home, scanDate: minutes(time), now: minutes(time)
        ) else { return [] }
        return events
    }

    func seen(_ ip: String, name: String? = "studio", mac: String? = nil, hosts: [String] = []) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: name, vendor: nil, macAddress: mac, latency: 3, discoveredAt: start, source: .bonjour,
            networkProfileID: home, bonjourClaims: hosts.map { HostClaim(host: $0, service: "Studio", address: ip) }
        )
    }

    let router = DiscoveredDevice(
        ipAddress: "10.0.0.1", hostname: "router", vendor: nil, macAddress: "AA:00:00:00:00:01", latency: 1, discoveredAt: Date(),
        source: .local
    )

    var routerSeen: DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: "10.0.0.1", hostname: "router", vendor: nil, macAddress: "AA:00:00:00:00:01", latency: 1, discoveredAt: start,
            source: .local, networkProfileID: home
        )
    }

    func devices() throws -> [DeviceProjection] {
        try DeviceGroups.project(ModelContext(container).fetch(FetchDescriptor<LocalDevice>()))
    }

    func kinds(_ events: [DeviceEvent]) -> [DeviceEvent.Kind] {
        events.map(\.kind)
    }

    @Test("A Mac answering on two addresses under one strong host becomes one device, which joins once")
    func dualHomedJoinsOnce() throws {
        try reconcile([routerSeen], at: 0)
        let events = try reconcile([routerSeen, seen("10.0.0.10", hosts: ["studio.local"]), seen("10.0.0.40", hosts: ["studio.local"])], at: 5)
        let studio = try #require(try devices().first { $0.isGroup })
        #expect(studio.members.count == 2)
        #expect(studio.members.allSatisfy { $0.groupSource == DeviceGroupSource.bonjour.rawValue })
        #expect(kinds(events) == [.joined])
        #expect(events.first?.deviceID == studio.id)
        #expect(delivered.count == 1 && delivered.last?.events == events, "the baseline scan had nothing to deliver")
    }

    @Test("The network's first recorded scan is the baseline: nothing joins")
    func baselineHasNoJoined() throws {
        #expect(try reconcile([routerSeen, seen("10.0.0.10", hosts: ["studio.local"]), seen("10.0.0.40", hosts: ["studio.local"])], at: 0).isEmpty)
    }

    @Test("Two offline rows that come back together under one host are one device coming online: one event")
    func unionComesOnlineOnce() throws {
        try reconcile([routerSeen, seen("10.0.0.10", name: "studio"), seen("10.0.0.40", name: "studio-wifi")], at: 0)
        for (index, time) in [20.0, 40, 60].enumerated() {
            try reconcile([routerSeen], at: time)
            _ = index
        }
        #expect(try devices().filter { !$0.isGroup && $0.ipAddress != "10.0.0.1" }.allSatisfy { $0.primary.status == .offline })
        let events = try reconcile(
            [routerSeen, seen("10.0.0.10", name: "studio", hosts: ["studio.local"]), seen("10.0.0.40", name: "studio-wifi", hosts: ["studio.local"])],
            at: 80
        )
        #expect(try devices().contains { $0.isGroup })
        #expect(kinds(events) == [.cameOnline])
    }

    @Test("One interface going quiet while another answers is no event; the last one going is one")
    func memberOfflineIsNoEvent() throws {
        try reconcile([routerSeen], at: 0)
        try reconcile([routerSeen, seen("10.0.0.10", hosts: ["studio.local"]), seen("10.0.0.40", hosts: ["studio.local"])], at: 5)
        var events: [DeviceEvent] = []
        for time in [25.0, 45, 65] {
            events += try reconcile([routerSeen, seen("10.0.0.40", hosts: ["studio.local"])], at: time)
        }
        #expect(events.isEmpty, "the Wi-Fi interface answered: the device never left")
        #expect(try devices().first { $0.isGroup }?.members.contains { $0.status == .offline } == true)
        var gone: [DeviceEvent] = []
        for time in [85.0, 105, 125] {
            gone += try reconcile([routerSeen], at: time)
        }
        #expect(gone.map(\.kind) == [.wentOffline(since: minutes(65))])
    }

    @Test("The current interface switching (wired to Wi-Fi) is no event")
    func interfaceSwitchIsNoEvent() throws {
        try reconcile([routerSeen], at: 0)
        try reconcile([routerSeen, seen("10.0.0.10", hosts: ["studio.local"]), seen("10.0.0.40", hosts: ["studio.local"])], at: 5)
        #expect(try reconcile([routerSeen, seen("10.0.0.40", hosts: ["studio.local"])], at: 10).isEmpty)
        #expect(try reconcile([routerSeen, seen("10.0.0.10", hosts: ["studio.local"])], at: 15).isEmpty)
    }

    @Test("A real DHCP move of the current interface during a scan that groups is an address change")
    func dhcpMoveDuringGrouping() throws {
        try reconcile([routerSeen, seen("10.0.0.10", mac: "AA:BB:CC:00:00:10")], at: 0)
        let events = try reconcile(
            [routerSeen, seen("10.0.0.12", mac: "AA:BB:CC:00:00:10", hosts: ["studio.local"]), seen("10.0.0.40", hosts: ["studio.local"])], at: 5
        )
        #expect(try devices().contains { $0.isGroup })
        // The Wi-Fi interface joining is membership only; the wired interface's move is real.
        #expect(kinds(events) == [.addressChanged(from: "10.0.0.10")])
    }

    @Test("A real rename of the primary is one event; a row joining another's group renames nothing")
    func renameAndPrimaryChange() throws {
        // With MACs, so a new name at the same address is the same device renamed (without one, a
        // different name at an address is another device: PresenceMatch).
        let wired = "AA:BB:CC:00:00:10", wifi = "AA:BB:CC:00:00:40", spare = "AA:BB:CC:00:00:41"
        try reconcile([routerSeen], at: 0)
        try reconcile(
            [routerSeen, seen("10.0.0.10", mac: wired, hosts: ["studio.local"]), seen("10.0.0.40", mac: wifi, hosts: ["studio.local"])], at: 5
        )
        let renamed = try reconcile([routerSeen, seen("10.0.0.10", name: "studio-pro", mac: wired, hosts: ["studio.local"])], at: 10)
        #expect(kinds(renamed) == [.renamed(from: "studio")])
        // A third interface, named differently, joins the group: the primary and its name stay.
        let joined = try reconcile([
            routerSeen, seen("10.0.0.10", name: "studio-pro", mac: wired, hosts: ["studio.local"]),
            seen("10.0.0.41", name: "eth2", mac: spare, hosts: ["studio.local"])
        ], at: 15)
        #expect(joined.isEmpty)
        #expect(try devices().first { $0.isGroup }?.members.count == 3)
    }

    @Test("#603: a different name at a known device's address without MACs is a newcomer joining, then the old device leaves")
    func dhcpReuseWithoutMACs() throws {
        try reconcile([routerSeen, seen("10.0.0.20", name: "nas")], at: 0)
        let joined = try reconcile([routerSeen, seen("10.0.0.20", name: "tv")], at: 5)
        #expect(kinds(joined) == [.joined])
        #expect(joined.first?.matchName == "tv")
        var later: [DeviceEvent] = []
        for time in [25.0, 45] {
            later += try reconcile([routerSeen, seen("10.0.0.20", name: "tv")], at: time)
        }
        #expect(later.count == 1)
        #expect(later.first?.matchName == "nas")
        if case .wentOffline = later.first?.kind {} else {
            Issue.record("expected the old device to go offline")
        }
    }

    @Test("A scan reconciled twice delivers once")
    func deliversOnce() throws {
        try reconcile([routerSeen], at: 0)
        try reconcile([routerSeen, seen("10.0.0.30", name: "printer")], at: 5)
        try reconcile([routerSeen, seen("10.0.0.30", name: "printer")], at: 5)
        #expect(delivered.count == 1, "the baseline had nothing; the repeat was skipped")
    }

    @Test("The end state doesn't depend on the scan's order: memberships, primary, addresses and events")
    func permutations() throws {
        let scan = [
            routerSeen,
            seen("10.0.0.10", hosts: ["studio.local"]),
            seen("10.0.0.40", mac: "AA:BB:CC:00:00:40", hosts: ["studio.local"]),
            seen("10.0.0.41", mac: "AA:BB:CC:00:00:40", hosts: ["studio.local"]),
            seen("10.0.0.50", name: "printer", hosts: ["printer-room.local", "office.local"])
        ]
        var outcomes: Set<String> = []
        for order in DeviceGroupingPlanTests.permutations(of: Array(scan.indices)) {
            let container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let suite = "ScanReconcilerGroupingTests.perm.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let reconciler = ScanReconciler(context: container.mainContext, history: ScanHistory(defaults: defaults))
            try reconciler.reconcile([routerSeen], networkProfileID: home, scanDate: minutes(0), now: minutes(0))
            guard case let .applied(_, _, events) = try reconciler.reconcile(
                order.map { scan[$0] }, networkProfileID: home, scanDate: minutes(5), now: minutes(5)
            ) else { continue }
            let devices = try DeviceGroups.project(ModelContext(container).fetch(FetchDescriptor<LocalDevice>()))
            let summary = devices.map { device in
                "\(device.members.map(\.ipAddress).sorted())|primary:\(device.primary.ipAddress)|current:\(device.ipAddress)"
            }.sorted().joined(separator: ";")
            let eventSummary = events.map { "\($0.kind)@\($0.ipAddress)" }.sorted().joined(separator: ",")
            outcomes.insert(summary + "#" + eventSummary)
        }
        #expect(outcomes.count == 1, "\(outcomes)")
    }
}
