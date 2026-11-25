import Testing
import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
@testable import NetMonitor_iOS

/// #583: the iPhone's device list and dashboard card show the network's saved rows with their
/// presence, plus the scan's devices not saved yet, sorted and filtered by presence, with past
/// devices behind "Show past devices (N)".
@Suite("SavedDeviceList")
@MainActor
struct SavedDeviceListTests {
    private let scan = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let home = UUID()
    private let day: TimeInterval = 86400

    private func row(
        _ ip: String, network: UUID?, mac: String = "", status: DeviceStatus = .online, lastSeen: Date, latency: Double? = nil
    ) -> LocalDevice {
        let row = LocalDevice(ipAddress: ip, macAddress: mac, hostname: "host-\(ip)", status: status, lastLatency: latency, networkProfileID: network)
        row.lastSeen = lastSeen
        return row
    }

    private func live(_ ip: String, mac: String? = nil, network: UUID?) -> DiscoveredDevice {
        DiscoveredDevice(ipAddress: ip, hostname: "live-\(ip)", vendor: nil,
            macAddress: mac, latency: 3, discoveredAt: scan, source: .local, networkProfileID: network)
    }

    private var presence: PresenceSnapshot {
        PresenceSnapshot(lastScans: [home: scan], now: scan + 60)
    }

    private func ips(_ list: SavedDeviceList) -> [String] {
        list.entries.map(\.ipAddress)
    }

    @Test func onlyTheNetworksRowsAndRowsWithoutANetworkAreListed() {
        let rows = [
            row("192.168.1.10", network: home, lastSeen: scan),
            row("192.168.1.11", network: nil, lastSeen: scan),
            row("10.0.0.2", network: UUID(), lastSeen: scan)
        ]
        let list = SavedDeviceList(saved: rows, network: home, sort: .ip, showPast: false, presence: presence)
        #expect(ips(list) == ["192.168.1.10", "192.168.1.11"])
    }

    @Test func pastDevicesAreHiddenAndCountedUntilShown() {
        let rows = [
            row("192.168.1.10", network: home, lastSeen: scan),
            row("192.168.1.20", network: home, status: .offline, lastSeen: scan - 8 * day)
        ]
        let hidden = SavedDeviceList(saved: rows, network: home, sort: .ip, showPast: false, presence: presence)
        #expect(ips(hidden) == ["192.168.1.10"])
        #expect(hidden.pastCount == 1)
        let shown = SavedDeviceList(saved: rows, network: home, sort: .ip, showPast: true, presence: presence)
        #expect(ips(shown) == ["192.168.1.10", "192.168.1.20"])
        #expect(shown.pastCount == 1)
    }

    @Test func statusSortPutsOnlineFirstThenOffline() {
        let rows = [
            row("192.168.1.5", network: home, status: .offline, lastSeen: scan - 3600),
            row("192.168.1.9", network: home, lastSeen: scan)
        ]
        let list = SavedDeviceList(saved: rows, network: home, sort: .status, showPast: false, presence: presence)
        #expect(ips(list) == ["192.168.1.9", "192.168.1.5"])
    }

    @Test func ipSortIsNumeric() {
        let rows = [row("192.168.1.100", network: home, lastSeen: scan), row("192.168.1.9", network: home, lastSeen: scan)]
        let list = SavedDeviceList(saved: rows, network: home, sort: .ip, showPast: false, presence: presence)
        #expect(ips(list) == ["192.168.1.9", "192.168.1.100"])
    }

    @Test func onlineCountUsesFreshnessNotTheSavedStatus() {
        let rows = [row("192.168.1.10", network: home, lastSeen: scan), row("192.168.1.11", network: home, status: .offline, lastSeen: scan)]
        let fresh = SavedDeviceList(saved: rows, network: home, sort: .ip, showPast: false, presence: presence)
        #expect(fresh.onlineCount == 1)
        let stale = SavedDeviceList(
            saved: rows, network: home, sort: .ip, showPast: false, presence: PresenceSnapshot(lastScans: [home: scan], now: scan + 3600)
        )
        #expect(stale.onlineCount == 0)
    }

    @Test func latencyShowsOnlyWhileOnline() {
        let online = row("192.168.1.10", network: home, lastSeen: scan, latency: 4)
        let offline = row("192.168.1.11", network: home, status: .offline, lastSeen: scan - 3600, latency: 9)
        let list = SavedDeviceList(saved: [online, offline], network: home, sort: .ip, showPast: false, presence: presence)
        #expect(list.latencyText(online) == "4 ms")
        #expect(list.latencyText(offline) == nil)
    }

    // MARK: - The scan's devices not saved yet

    @Test func midScanANewDeviceAppearsAsFoundInThisScan() {
        let rows = [row("192.168.1.10", network: home, mac: "AA:00:00:00:00:10", lastSeen: scan)]
        let list = SavedDeviceList(
            saved: rows, live: [live("192.168.1.10", mac: "AA:00:00:00:00:10", network: home), live("192.168.1.42", network: home)],
            network: home, sort: .ip, showPast: false, presence: presence
        )
        #expect(ips(list) == ["192.168.1.10", "192.168.1.42"])
        guard case .found(let device) = list.entries[1] else {
            Issue.record("The new device should be found in this scan")
            return
        }
        #expect(device.ipAddress == "192.168.1.42")
        #expect(list.onlineCount == 2)
    }

    /// A stopped scan leaves its devices in the live list, so they still show until the next scan.
    @Test func afterAStoppedScanItsDevicesStillShowUnsaved() {
        let list = SavedDeviceList(saved: [], live: [live("192.168.1.42", network: home)], network: home, sort: .ip, showPast: false,
            presence: presence)
        #expect(ips(list) == ["192.168.1.42"])
    }

    @Test func aSavedDeviceAlsoInTheScanIsListedOnce() {
        let rows = [
            row("192.168.1.10", network: home, mac: "AA:00:00:00:00:10", lastSeen: scan),
            row("192.168.1.11", network: home, lastSeen: scan)
        ]
        let scanned = [
            // The same MAC at a new address, and a device without a MAC at a saved address.
            live("192.168.1.30", mac: "aa:00:00:00:00:10", network: home),
            live("192.168.1.11", network: home)
        ]
        let list = SavedDeviceList(saved: rows, live: scanned, network: home, sort: .ip, showPast: false, presence: presence)
        #expect(ips(list) == ["192.168.1.10", "192.168.1.11"])
        #expect(list.entries.allSatisfy {
            if case .saved = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test func anotherNetworksScannedDevicesAreNotListed() {
        let list = SavedDeviceList(saved: [], live: [live("10.0.0.2", network: UUID())], network: home, sort: .ip, showPast: false,
            presence: presence)
        #expect(list.entries.isEmpty)
    }
}

/// #583: presence is read again once a scan is saved, so rows don't read "Not checked recently"
/// for up to a minute after a fresh scan.
@Suite("DevicePresenceModel", .serialized)
@MainActor
struct DevicePresenceModelTests {
    @Test func aSavedScanRefreshesPresenceAtOnce() throws {
        let suite = "DevicePresenceModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = ScanHistory(defaults: defaults)
        let home = UUID()
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let model = DevicePresenceModel(history: history, clock: { now })
        #expect(!model.snapshot.isNetworkChecked(home))

        let discovery = MockDeviceDiscoveryService()
        let schema = Schema([LocalDevice.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let updater = DeviceRecordUpdater(
            discoveryService: discovery,
            reconciler: ScanReconciler(context: container.mainContext, history: history),
            currentNetworkProfileID: { home },
            clock: { now },
            onSaved: { model.refresh() }
        )
        discovery.isScanning = true
        updater.handleScanChange()
        discovery.discoveredDevices = [
            DiscoveredDevice(ipAddress: "192.168.1.10", hostname: "a", vendor: nil, macAddress: nil, latency: 3, discoveredAt: now, source: .local)
        ]
        discovery.lastScanDate = now
        discovery.isScanning = false
        updater.handleScanChange()

        #expect(model.snapshot.isNetworkChecked(home))
    }
}
