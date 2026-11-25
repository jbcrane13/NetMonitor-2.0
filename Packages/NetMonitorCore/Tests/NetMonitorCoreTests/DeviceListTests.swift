import Testing
import Foundation
@testable import NetMonitorCore

// MARK: - Helpers

private func makeDevice(
    ipAddress: String = "192.168.1.100",
    macAddress: String = "AA:BB:CC:DD:EE:FF",
    hostname: String? = nil,
    vendor: String? = nil,
    customName: String? = nil,
    status: DeviceStatus = .online,
    lastLatency: Double? = nil,
    resolvedHostname: String? = nil
) -> LocalDevice {
    LocalDevice(
        ipAddress: ipAddress,
        macAddress: macAddress,
        hostname: hostname,
        vendor: vendor,
        customName: customName,
        status: status,
        lastLatency: lastLatency,
        resolvedHostname: resolvedHostname
    )
}

/// Every network scanned a minute ago: saved statuses read as they are.
private var fresh: PresenceSnapshot {
    PresenceSnapshot(lastScans: [nil: Date(timeIntervalSinceNow: -60)], now: Date())
}

// MARK: - Search

struct DeviceListSearchTests {

    @Test("Matches display name case-insensitively")
    func matchesDisplayName() {
        let devices = [
            makeDevice(customName: "Kitchen Sonos"),
            makeDevice(customName: "Office Printer")
        ]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(search: "sonos", showPast: true),
            presence: fresh, sort: .name, ascending: true)
        #expect(result.map(\.displayName) == ["Kitchen Sonos"])
    }

    @Test("Matches IP address by substring containment")
    func matchesIPAddress() {
        let devices = [
            makeDevice(ipAddress: "192.168.1.42"),
            makeDevice(ipAddress: "10.0.0.5")
        ]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(search: "168.1.4", showPast: true),
            presence: fresh, sort: .name, ascending: true)
        #expect(result.map(\.ipAddress) == ["192.168.1.42"])
    }

    @Test("Matches MAC address case-insensitively")
    func matchesMACAddress() {
        let devices = [
            makeDevice(macAddress: "AA:BB:CC:DD:EE:FF"),
            makeDevice(macAddress: "11:22:33:44:55:66")
        ]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(search: "aa:bb:cc", showPast: true),
            presence: fresh, sort: .name, ascending: true)
        #expect(result.map(\.macAddress) == ["AA:BB:CC:DD:EE:FF"])
    }

    @Test("Matches vendor case-insensitively")
    func matchesVendor() {
        let devices = [
            makeDevice(vendor: "Apple, Inc."),
            makeDevice(vendor: "Samsung")
        ]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(search: "apple", showPast: true),
            presence: fresh, sort: .name, ascending: true)
        #expect(result.map(\.vendor) == ["Apple, Inc."])
    }

    @Test("Devices with nil vendor are excluded from a vendor search")
    func nilVendorExcluded() {
        let devices = [
            makeDevice(vendor: nil, customName: "No Vendor Device")
        ]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(search: "apple", showPast: true),
            presence: fresh, sort: .name, ascending: true)
        #expect(result.isEmpty)
    }

    @Test("Empty search returns all devices")
    func emptySearchReturnsAll() {
        let devices = [makeDevice(customName: "A"), makeDevice(customName: "B")]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(showPast: true),
            presence: fresh, sort: .name, ascending: true)
        #expect(result.count == 2)
    }
}

// MARK: - Online only

struct DeviceListOnlineOnlyTests {

    @Test("Filters to online devices only")
    func filtersOnlineOnly() {
        let devices = [
            makeDevice(customName: "Online", status: .online),
            makeDevice(customName: "Offline", status: .offline)
        ]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(onlineOnly: true, showPast: true),
            presence: fresh, sort: .name, ascending: true)
        #expect(result.map(\.displayName) == ["Online"])
    }

    @Test("onlineOnly false includes all statuses")
    func onlineOnlyFalseIncludesAll() {
        let devices = [
            makeDevice(customName: "Online", status: .online),
            makeDevice(customName: "Offline", status: .offline)
        ]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(showPast: true),
            presence: fresh, sort: .name, ascending: true)
        #expect(result.count == 2)
    }
}

// MARK: - Sort orders

struct DeviceListSortTests {

    @Test("lastSeen defaults to descending (most recent first)")
    func lastSeenDefaultsDescending() {
        let older = makeDevice(customName: "Older")
        older.lastSeen = Date(timeIntervalSinceNow: -3600)
        let newer = makeDevice(customName: "Newer")
        newer.lastSeen = Date()

        let result = DeviceList.rows([older, newer], filter: DeviceListFilter(showPast: true),
            presence: fresh, sort: .lastSeen, ascending: false)
        #expect(result.map(\.displayName) == ["Newer", "Older"])
    }

    @Test("lastSeen ascending true reverses to oldest first")
    func lastSeenAscendingReverses() {
        let older = makeDevice(customName: "Older")
        older.lastSeen = Date(timeIntervalSinceNow: -3600)
        let newer = makeDevice(customName: "Newer")
        newer.lastSeen = Date()

        let result = DeviceList.rows([older, newer], filter: DeviceListFilter(showPast: true),
            presence: fresh, sort: .lastSeen, ascending: true)
        #expect(result.map(\.displayName) == ["Older", "Newer"])
    }

    @Test("name sorts ascending by default")
    func nameAscendingDefault() {
        let devices = [makeDevice(customName: "Bravo"), makeDevice(customName: "Alpha")]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(showPast: true),
            presence: fresh, sort: .name, ascending: true)
        #expect(result.map(\.displayName) == ["Alpha", "Bravo"])
    }

    @Test("name sorts descending when ascending is false")
    func nameDescendingWhenFalse() {
        let devices = [makeDevice(customName: "Bravo"), makeDevice(customName: "Alpha")]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(showPast: true),
            presence: fresh, sort: .name, ascending: false)
        #expect(result.map(\.displayName) == ["Bravo", "Alpha"])
    }

    @Test("ipAddress sorts numerically ascending by default")
    func ipAddressAscendingDefault() {
        let devices = [
            makeDevice(ipAddress: "192.168.2.10", customName: "Ten"),
            makeDevice(ipAddress: "192.168.2.3", customName: "Three")
        ]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(showPast: true),
            presence: fresh, sort: .ipAddress, ascending: true)
        #expect(result.map(\.displayName) == ["Three", "Ten"])
    }

    @Test("ipAddress sorts descending when ascending is false")
    func ipAddressDescendingWhenFalse() {
        let devices = [
            makeDevice(ipAddress: "192.168.2.10", customName: "Ten"),
            makeDevice(ipAddress: "192.168.2.3", customName: "Three")
        ]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(showPast: true),
            presence: fresh, sort: .ipAddress, ascending: false)
        #expect(result.map(\.displayName) == ["Ten", "Three"])
    }

    @Test("status sorts online-first by default")
    func statusAscendingDefault() {
        let devices = [
            makeDevice(customName: "Offline", status: .offline),
            makeDevice(customName: "Online", status: .online)
        ]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(showPast: true),
            presence: fresh, sort: .status, ascending: true)
        #expect(result.map(\.displayName) == ["Online", "Offline"])
    }

    @Test("status sorts offline-first when ascending is false")
    func statusDescendingWhenFalse() {
        let devices = [
            makeDevice(customName: "Offline", status: .offline),
            makeDevice(customName: "Online", status: .online)
        ]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(showPast: true),
            presence: fresh, sort: .status, ascending: false)
        #expect(result.map(\.displayName) == ["Offline", "Online"])
    }

    @Test("vendor sorts ascending by default, nil treated as last")
    func vendorAscendingDefault() {
        let devices = [
            makeDevice(vendor: nil, customName: "NoVendor"),
            makeDevice(vendor: "Apple", customName: "AppleDevice")
        ]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(showPast: true),
            presence: fresh, sort: .vendor, ascending: true)
        #expect(result.map(\.displayName) == ["AppleDevice", "NoVendor"])
    }

    @Test("vendor sorts descending when ascending is false")
    func vendorDescendingWhenFalse() {
        let devices = [
            makeDevice(vendor: nil, customName: "NoVendor"),
            makeDevice(vendor: "Apple", customName: "AppleDevice")
        ]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(showPast: true),
            presence: fresh, sort: .vendor, ascending: false)
        #expect(result.map(\.displayName) == ["NoVendor", "AppleDevice"])
    }

    @Test("latency sorts ascending by default, nil treated as infinite")
    func latencyAscendingDefault() {
        let devices = [
            makeDevice(customName: "NoLatency", lastLatency: nil),
            makeDevice(customName: "Fast", lastLatency: 5.0)
        ]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(showPast: true),
            presence: fresh, sort: .latency, ascending: true)
        #expect(result.map(\.displayName) == ["Fast", "NoLatency"])
    }

    @Test("latency sorts descending when ascending is false")
    func latencyDescendingWhenFalse() {
        let devices = [
            makeDevice(customName: "NoLatency", lastLatency: nil),
            makeDevice(customName: "Fast", lastLatency: 5.0)
        ]
        let result = DeviceList.rows(devices, filter: DeviceListFilter(showPast: true),
            presence: fresh, sort: .latency, ascending: false)
        #expect(result.map(\.displayName) == ["NoLatency", "Fast"])
    }
}

// MARK: - compareIPAddresses

struct DeviceListCompareIPAddressesTests {

    @Test("Compares octets numerically, not lexicographically")
    func numericOctetOrdering() {
        #expect(DeviceList.compareIPAddresses("192.168.2.3", "192.168.2.10") == true)
        #expect(DeviceList.compareIPAddresses("192.168.2.10", "192.168.2.3") == false)
    }

    @Test("Equal addresses compare false")
    func equalAddresses() {
        #expect(DeviceList.compareIPAddresses("10.0.0.1", "10.0.0.1") == false)
    }
}

// MARK: - Presence freshness (#583)

struct DeviceListPresenceTests {
    private let scan = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let home = UUID()
    private let away = UUID()
    private let day: TimeInterval = 86400

    private func device(_ name: String, network: UUID?, status: DeviceStatus = .online, lastSeen: Date) -> LocalDevice {
        let row = LocalDevice(ipAddress: "192.168.1.\(name.count)", macAddress: "", customName: name, status: status, networkProfileID: network)
        row.lastSeen = lastSeen
        return row
    }

    /// `home` scanned at `scan`, `away` an hour before; now is five minutes after `scan`.
    private var presence: PresenceSnapshot {
        PresenceSnapshot(lastScans: [home: scan, away: scan - 3600], now: scan + 300)
    }

    @Test func onlineOnlyDropsRowsWhoseNetworkWasNotCheckedRecently() {
        let rows = [
            device("Fresh", network: home, lastSeen: scan),
            device("Stale", network: away, lastSeen: scan - 3600),
            device("Unassigned", network: nil, lastSeen: scan)
        ]
        let result = DeviceList.rows(rows, filter: DeviceListFilter(onlineOnly: true), presence: presence, sort: .name, ascending: true)
        #expect(result.map(\.displayName) == ["Fresh"])
    }

    @Test func aRowSavedWithoutANetworkReadsFromTheScansMadeWithoutOne() {
        let row = device("Unassigned", network: nil, lastSeen: scan)
        #expect(presence.freshness(of: row) == .notCheckedRecently)
        let scannedWithout = PresenceSnapshot(lastScans: [nil: scan], now: scan + 300)
        #expect(scannedWithout.freshness(of: row) == .online)
    }

    @Test func statusSortsOnlineThenNotCheckedThenOffline() {
        let rows = [
            device("Offline", network: home, status: .offline, lastSeen: scan - 3600),
            device("Stale", network: away, lastSeen: scan - 3600),
            device("Online", network: home, lastSeen: scan)
        ]
        let ascending = DeviceList.rows(rows, filter: DeviceListFilter(showPast: true), presence: presence, sort: .status, ascending: true)
        #expect(ascending.map(\.displayName) == ["Online", "Stale", "Offline"])
        let descending = DeviceList.rows(rows, filter: DeviceListFilter(showPast: true), presence: presence, sort: .status, ascending: false)
        #expect(descending.map(\.displayName) == ["Offline", "Stale", "Online"])
    }

    @Test func pastDevicesAreHiddenUnlessShownAndCounted() {
        let rows = [
            device("Recent", network: home, status: .offline, lastSeen: scan - 6 * day),
            device("Past", network: home, status: .offline, lastSeen: scan - 8 * day),
            device("Old past", network: home, status: .offline, lastSeen: scan - 30 * day)
        ]
        let hidden = DeviceList.rows(rows, filter: DeviceListFilter(), presence: presence, sort: .name, ascending: true)
        #expect(hidden.map(\.displayName) == ["Recent"])
        #expect(DeviceList.pastCount(rows, filter: DeviceListFilter(), presence: presence) == 2)
        #expect(DeviceList.pastCount(rows, filter: DeviceListFilter(search: "old"), presence: presence) == 1)
        // Online Only shows no offline device, so showing past devices would add none.
        #expect(DeviceList.pastCount(rows, filter: DeviceListFilter(onlineOnly: true), presence: presence) == 0)
        let shown = DeviceList.rows(rows, filter: DeviceListFilter(showPast: true), presence: presence, sort: .name, ascending: true)
        #expect(shown.count == 3)
    }

    @Test func aSnapshotFromScanHistoryReadsEachNetworksLatestReconciledScan() throws {
        let suite = "DeviceListPresenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = ScanHistory(defaults: defaults)
        history.record(scan: scan, reconciled: scan + 1, for: home)
        history.record(scan: scan + 600, reconciled: scan + 601, for: home)
        #expect(history.lastScanTime(for: home) == scan + 601)
        history.record(scan: scan, reconciled: scan + 2, for: nil)
        let snapshot = history.presenceSnapshot(now: scan + 700)
        #expect(snapshot.lastScan(for: home) == scan + 601)
        #expect(snapshot.lastScan(for: nil) == scan + 2)
        #expect(snapshot.lastScan(for: away) == nil)
        #expect(snapshot.now == scan + 700)
    }
}
