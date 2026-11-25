import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_iOS

/// #583: the iPhone's device list and dashboard card show the network's saved rows with their
/// presence, sorted and filtered by it, with past devices behind "Show past devices (N)".
@Suite("SavedDeviceList")
@MainActor
struct SavedDeviceListTests {
    private let scan = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let home = UUID()
    private let day: TimeInterval = 86400

    private func row(_ ip: String, network: UUID?, status: DeviceStatus = .online, lastSeen: Date, latency: Double? = nil) -> LocalDevice {
        let row = LocalDevice(ipAddress: ip, macAddress: "", hostname: "host-\(ip)", status: status, lastLatency: latency, networkProfileID: network)
        row.lastSeen = lastSeen
        return row
    }

    private var presence: PresenceSnapshot {
        PresenceSnapshot(lastScans: [home: scan], now: scan + 60)
    }

    @Test func onlyTheNetworksRowsAreListed() {
        let rows = [row("192.168.1.10", network: home, lastSeen: scan), row("10.0.0.2", network: UUID(), lastSeen: scan)]
        let list = SavedDeviceList(saved: rows, network: home, sort: .ip, showPast: false, presence: presence)
        #expect(list.rows.map(\.ipAddress) == ["192.168.1.10"])
    }

    @Test func pastDevicesAreHiddenAndCountedUntilShown() {
        let rows = [
            row("192.168.1.10", network: home, lastSeen: scan),
            row("192.168.1.20", network: home, status: .offline, lastSeen: scan - 8 * day)
        ]
        let hidden = SavedDeviceList(saved: rows, network: home, sort: .ip, showPast: false, presence: presence)
        #expect(hidden.rows.map(\.ipAddress) == ["192.168.1.10"])
        #expect(hidden.pastCount == 1)
        let shown = SavedDeviceList(saved: rows, network: home, sort: .ip, showPast: true, presence: presence)
        #expect(shown.rows.map(\.ipAddress) == ["192.168.1.10", "192.168.1.20"])
        #expect(shown.pastCount == 1)
    }

    @Test func statusSortPutsOnlineFirstThenOffline() {
        let rows = [
            row("192.168.1.5", network: home, status: .offline, lastSeen: scan - 3600),
            row("192.168.1.9", network: home, lastSeen: scan)
        ]
        let list = SavedDeviceList(saved: rows, network: home, sort: .status, showPast: false, presence: presence)
        #expect(list.rows.map(\.ipAddress) == ["192.168.1.9", "192.168.1.5"])
    }

    @Test func ipSortIsNumeric() {
        let rows = [row("192.168.1.100", network: home, lastSeen: scan), row("192.168.1.9", network: home, lastSeen: scan)]
        let list = SavedDeviceList(saved: rows, network: home, sort: .ip, showPast: false, presence: presence)
        #expect(list.rows.map(\.ipAddress) == ["192.168.1.9", "192.168.1.100"])
    }

    @Test func onlineCountUsesFreshnessNotTheSavedStatus() {
        let rows = [row("192.168.1.10", network: home, lastSeen: scan), row("192.168.1.11", network: home, status: .offline, lastSeen: scan)]
        let fresh = SavedDeviceList(saved: rows, network: home, sort: .ip, showPast: false, presence: presence)
        #expect(fresh.onlineCount == 1)
        let stale = SavedDeviceList(
            saved: rows, network: home, sort: .ip, showPast: false, presence: PresenceSnapshot(lastScans: [home: scan], now: scan + 3600)
        )
        #expect(stale.onlineCount == 0)
        #expect(stale.rows.allSatisfy { stale.presence.freshness(of: $0) == .notCheckedRecently })
    }

    @Test func latencyShowsOnlyWhileOnline() {
        let online = row("192.168.1.10", network: home, lastSeen: scan, latency: 4)
        let offline = row("192.168.1.11", network: home, status: .offline, lastSeen: scan - 3600, latency: 9)
        let list = SavedDeviceList(saved: [online, offline], network: home, sort: .ip, showPast: false, presence: presence)
        #expect(list.latencyText(online) == "4 ms")
        #expect(list.latencyText(offline) == nil)
    }

    @Test func aRowSaysItsStateAndLastSeen() {
        let offline = row("192.168.1.11", network: home, status: .offline, lastSeen: scan - 30 * 60)
        let list = SavedDeviceList(saved: [offline], network: home, sort: .ip, showPast: false, presence: presence)
        #expect(list.statusText(offline) == "Offline · Last seen 31 min ago")
    }
}
