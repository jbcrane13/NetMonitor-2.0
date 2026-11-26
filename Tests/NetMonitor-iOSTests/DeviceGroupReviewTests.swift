import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_iOS

/// #615 review round 2, iPhone side. Same fixture as `DeviceGroupReaderTests`: "Studio Mac" is a
/// wired primary at 192.168.1.60 (offline) and a Wi-Fi interface at 192.168.1.13 (current).
extension DeviceGroupReaderTests {
    // MARK: - Removing the primary keeps references

    /// iOS keeps row IDs only in Timeline entries: rules become monitoring targets that name a host,
    /// with no device ID. Deleting the primary while a Timeline entry and an open detail view name
    /// it: the entry follows the device, and detail moves on to the remaining interface.
    @Test func removingThePrimaryRepointsTimelineEntriesAndDetailMovesOn() throws {
        let group = try seedGroup()
        let events = NetworkEventService()
        events.log(
            type: .deviceLeft, title: "Device Left: Studio Mac", details: "192.168.1.60", severity: .warning,
            deviceID: group.primary.id, networkProfileID: home
        )
        let viewModel = DeviceDetailViewModel(deviceDiscoveryService: MockDeviceDiscoveryService(), references: [events])
        viewModel.loadDevice(id: group.groupID, context: group.context)
        let memberID = group.member.id

        viewModel.removeInterface(group.primary)

        #expect(events.events.first?.deviceID == memberID)
        let resolver = try DeviceGroupResolver(rows: group.freshRows())
        #expect(events.events.first?.deviceID.flatMap { resolver.device(for: $0)?.id } == memberID)
        #expect(viewModel.device?.id == memberID)
        #expect(viewModel.device?.ipAddress == "192.168.1.13")
        #expect(viewModel.error == nil)
    }

    /// Rows saved before rows carried a network page by device too: 250 two-member groups among
    /// the newest 500 such rows still list 500 devices.
    @Test func rowsSavedWithoutANetworkPageByDevice() throws {
        let container = try makeContainer()
        let context = container.mainContext
        var groups: [[UUID]] = []
        for index in 0 ..< 250 {
            let pair = [filler(index * 2, lastSeen: scan - Double(index)), filler(index * 2 + 1, lastSeen: scan - Double(index))]
            for row in pair {
                row.networkProfileID = nil
                context.insert(row)
            }
            groups.append(pair.map(\.id))
        }
        for index in 500 ..< 800 {
            let row = filler(index, lastSeen: scan - 1000 - Double(index))
            row.networkProfileID = nil
            context.insert(row)
        }
        try context.save()
        let writer = DeviceGroupWriter(container: container)
        for pair in groups {
            try writer.group(pair, primary: pair[0], source: .user)
        }

        let devices = DeviceGroups.project(SavedDeviceList.recentRows(network: home, in: ModelContext(container)))
        #expect(devices.count == 500)
        #expect(devices.count(where: \.isGroup) == 250)
    }

    // MARK: - Ports belong to the selected interface

    /// Ethernet has SSH open, Wi-Fi nothing; the device's address is Wi-Fi's. The draft never
    /// targets Wi-Fi:22: the port check runs on Wi-Fi instead.
    @Test func aRuleTargetsOnlyPortsMeasuredOnTheSelectedInterface() async throws {
        let group = try seedGroup()
        group.primary.openPorts = [22]
        try group.context.save()
        let probed = ProbeLog()
        let parser = FixedRuleIntentParser(answers: [
            "Tell me if Studio Mac goes offline": RuleIntent(kind: .deviceOffline, device: "Studio Mac")
        ])
        let model = PlainRuleIOSViewModel(parser: parser, probe: MonitoringTargetProbe { host, port, _ in
            probed.record(host, port)
            return false
        })
        model.text = "Tell me if Studio Mac goes offline"
        let rows = try DeviceGroups.recentDevices(in: .network(home), limit: RuleDevice.candidateLimit, in: group.context).flatMap(\.members)

        await model.submit(devices: rows, targets: [], networkID: home, isScanning: false, context: group.context)

        #expect(model.targetDraft == nil, "No port is known open on Wi-Fi, and the check found none")
        #expect(!probed.calls.isEmpty)
        #expect(probed.calls.allSatisfy { $0.host == "192.168.1.13" }, "\(probed.calls)")
    }

    // MARK: - The widget

    /// A scan saved without a network (none was known) still updates the widget, from its own devices.
    @Test func aScanSavedWithoutANetworkStillPublishesTheWidget() throws {
        let container = try makeContainer()
        let defaults = try #require(UserDefaults(suiteName: "DeviceGroupReviewTests.\(UUID().uuidString)"))
        let scanned = ["192.168.1.2", "192.168.1.3", "192.168.1.10", "192.168.1.20"].map { ip in
            DiscoveredDevice(ipAddress: ip, hostname: "host-\(ip)", vendor: nil, macAddress: nil, latency: 3, discoveredAt: scan, source: .local)
        }
        let model = SavedDeviceSummaryModel()

        model.publish(savedScan: scanned, networks: [], in: container.mainContext, presence: presence, defaults: defaults, reloadWidget: false)

        #expect(defaults.integer(forKey: AppSettings.Keys.widgetDeviceCount) == 4)
        #expect(try topDevices(defaults).map { $0["ip"] } == ["192.168.1.2", "192.168.1.3", "192.168.1.10"])
    }

    /// The top three keep the order the widget had before #594: by address, as scans list devices.
    @Test func theWidgetsTopThreeAreTheFirstThreeByAddress() throws {
        let container = try makeContainer()
        for ip in ["192.168.1.100", "192.168.1.3", "192.168.1.20", "192.168.1.2"] {
            let row = LocalDevice(ipAddress: ip, macAddress: "", hostname: "host-\(ip)", status: .online, networkProfileID: home)
            row.lastSeen = scan
            container.mainContext.insert(row)
        }
        try container.mainContext.save()
        let defaults = try #require(UserDefaults(suiteName: "DeviceGroupReviewTests.\(UUID().uuidString)"))

        SavedDeviceSummaryModel().publish(
            savedScan: [], networks: [home], in: container.mainContext, presence: presence, defaults: defaults, reloadWidget: false
        )

        #expect(defaults.integer(forKey: AppSettings.Keys.widgetDeviceCount) == 4)
        #expect(try topDevices(defaults).map { $0["ip"] } == ["192.168.1.2", "192.168.1.3", "192.168.1.20"])
    }

    private func topDevices(_ defaults: UserDefaults) throws -> [[String: String]] {
        let data = try #require(defaults.data(forKey: AppSettings.Keys.widgetTopDevices))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: String]])
    }
}

/// The hosts and ports a port check was asked about.
final class ProbeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(host: String, port: Int)] = []

    var calls: [(host: String, port: Int)] {
        lock.withLock { recorded }
    }

    func record(_ host: String, _ port: Int) {
        lock.withLock { recorded.append((host, port)) }
    }

    /// #615 verification: the list reads its network's devices plus those saved without a network,
    /// through Core's scopes, never another network's.
    @Test @MainActor func theListReadsItsNetworkAndRowsWithoutANetworkOnly() throws {
        let container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let mine = UUID(), elsewhere = UUID()
        for row in [LocalDevice(ipAddress: "10.0.0.5", macAddress: ""), LocalDevice(ipAddress: "10.0.0.6", macAddress: "", networkProfileID: mine),
                    LocalDevice(ipAddress: "10.0.0.7", macAddress: "", networkProfileID: elsewhere)] {
            context.insert(row)
        }
        try context.save()
        #expect(Set(SavedDeviceList.recentRows(network: mine, in: context).map(\.ipAddress)) == ["10.0.0.5", "10.0.0.6"])
        #expect(SavedDeviceList.recentRows(network: nil, in: context).map(\.ipAddress) == ["10.0.0.5"])
    }
}
