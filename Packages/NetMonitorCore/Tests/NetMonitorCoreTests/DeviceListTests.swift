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

// MARK: - Search

struct DeviceListSearchTests {

    @Test("Matches display name case-insensitively")
    func matchesDisplayName() {
        let devices = [
            makeDevice(customName: "Kitchen Sonos"),
            makeDevice(customName: "Office Printer")
        ]
        let result = DeviceList.rows(devices, search: "sonos", onlineOnly: false, sort: .name, ascending: true)
        #expect(result.map(\.displayName) == ["Kitchen Sonos"])
    }

    @Test("Matches IP address by substring containment")
    func matchesIPAddress() {
        let devices = [
            makeDevice(ipAddress: "192.168.1.42"),
            makeDevice(ipAddress: "10.0.0.5")
        ]
        let result = DeviceList.rows(devices, search: "168.1.4", onlineOnly: false, sort: .name, ascending: true)
        #expect(result.map(\.ipAddress) == ["192.168.1.42"])
    }

    @Test("Matches MAC address case-insensitively")
    func matchesMACAddress() {
        let devices = [
            makeDevice(macAddress: "AA:BB:CC:DD:EE:FF"),
            makeDevice(macAddress: "11:22:33:44:55:66")
        ]
        let result = DeviceList.rows(devices, search: "aa:bb:cc", onlineOnly: false, sort: .name, ascending: true)
        #expect(result.map(\.macAddress) == ["AA:BB:CC:DD:EE:FF"])
    }

    @Test("Matches vendor case-insensitively")
    func matchesVendor() {
        let devices = [
            makeDevice(vendor: "Apple, Inc."),
            makeDevice(vendor: "Samsung")
        ]
        let result = DeviceList.rows(devices, search: "apple", onlineOnly: false, sort: .name, ascending: true)
        #expect(result.map(\.vendor) == ["Apple, Inc."])
    }

    @Test("Devices with nil vendor are excluded from a vendor search")
    func nilVendorExcluded() {
        let devices = [
            makeDevice(vendor: nil, customName: "No Vendor Device")
        ]
        let result = DeviceList.rows(devices, search: "apple", onlineOnly: false, sort: .name, ascending: true)
        #expect(result.isEmpty)
    }

    @Test("Empty search returns all devices")
    func emptySearchReturnsAll() {
        let devices = [makeDevice(customName: "A"), makeDevice(customName: "B")]
        let result = DeviceList.rows(devices, search: "", onlineOnly: false, sort: .name, ascending: true)
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
        let result = DeviceList.rows(devices, search: "", onlineOnly: true, sort: .name, ascending: true)
        #expect(result.map(\.displayName) == ["Online"])
    }

    @Test("onlineOnly false includes all statuses")
    func onlineOnlyFalseIncludesAll() {
        let devices = [
            makeDevice(customName: "Online", status: .online),
            makeDevice(customName: "Offline", status: .offline)
        ]
        let result = DeviceList.rows(devices, search: "", onlineOnly: false, sort: .name, ascending: true)
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

        let result = DeviceList.rows([older, newer], search: "", onlineOnly: false, sort: .lastSeen, ascending: false)
        #expect(result.map(\.displayName) == ["Newer", "Older"])
    }

    @Test("lastSeen ascending true reverses to oldest first")
    func lastSeenAscendingReverses() {
        let older = makeDevice(customName: "Older")
        older.lastSeen = Date(timeIntervalSinceNow: -3600)
        let newer = makeDevice(customName: "Newer")
        newer.lastSeen = Date()

        let result = DeviceList.rows([older, newer], search: "", onlineOnly: false, sort: .lastSeen, ascending: true)
        #expect(result.map(\.displayName) == ["Older", "Newer"])
    }

    @Test("name sorts ascending by default")
    func nameAscendingDefault() {
        let devices = [makeDevice(customName: "Bravo"), makeDevice(customName: "Alpha")]
        let result = DeviceList.rows(devices, search: "", onlineOnly: false, sort: .name, ascending: true)
        #expect(result.map(\.displayName) == ["Alpha", "Bravo"])
    }

    @Test("name sorts descending when ascending is false")
    func nameDescendingWhenFalse() {
        let devices = [makeDevice(customName: "Bravo"), makeDevice(customName: "Alpha")]
        let result = DeviceList.rows(devices, search: "", onlineOnly: false, sort: .name, ascending: false)
        #expect(result.map(\.displayName) == ["Bravo", "Alpha"])
    }

    @Test("ipAddress sorts numerically ascending by default")
    func ipAddressAscendingDefault() {
        let devices = [
            makeDevice(ipAddress: "192.168.2.10", customName: "Ten"),
            makeDevice(ipAddress: "192.168.2.3", customName: "Three")
        ]
        let result = DeviceList.rows(devices, search: "", onlineOnly: false, sort: .ipAddress, ascending: true)
        #expect(result.map(\.displayName) == ["Three", "Ten"])
    }

    @Test("ipAddress sorts descending when ascending is false")
    func ipAddressDescendingWhenFalse() {
        let devices = [
            makeDevice(ipAddress: "192.168.2.10", customName: "Ten"),
            makeDevice(ipAddress: "192.168.2.3", customName: "Three")
        ]
        let result = DeviceList.rows(devices, search: "", onlineOnly: false, sort: .ipAddress, ascending: false)
        #expect(result.map(\.displayName) == ["Ten", "Three"])
    }

    @Test("status sorts online-first by default")
    func statusAscendingDefault() {
        let devices = [
            makeDevice(customName: "Offline", status: .offline),
            makeDevice(customName: "Online", status: .online)
        ]
        let result = DeviceList.rows(devices, search: "", onlineOnly: false, sort: .status, ascending: true)
        #expect(result.map(\.displayName) == ["Online", "Offline"])
    }

    @Test("status sorts offline-first when ascending is false")
    func statusDescendingWhenFalse() {
        let devices = [
            makeDevice(customName: "Offline", status: .offline),
            makeDevice(customName: "Online", status: .online)
        ]
        let result = DeviceList.rows(devices, search: "", onlineOnly: false, sort: .status, ascending: false)
        #expect(result.map(\.displayName) == ["Offline", "Online"])
    }

    @Test("vendor sorts ascending by default, nil treated as last")
    func vendorAscendingDefault() {
        let devices = [
            makeDevice(vendor: nil, customName: "NoVendor"),
            makeDevice(vendor: "Apple", customName: "AppleDevice")
        ]
        let result = DeviceList.rows(devices, search: "", onlineOnly: false, sort: .vendor, ascending: true)
        #expect(result.map(\.displayName) == ["AppleDevice", "NoVendor"])
    }

    @Test("vendor sorts descending when ascending is false")
    func vendorDescendingWhenFalse() {
        let devices = [
            makeDevice(vendor: nil, customName: "NoVendor"),
            makeDevice(vendor: "Apple", customName: "AppleDevice")
        ]
        let result = DeviceList.rows(devices, search: "", onlineOnly: false, sort: .vendor, ascending: false)
        #expect(result.map(\.displayName) == ["NoVendor", "AppleDevice"])
    }

    @Test("latency sorts ascending by default, nil treated as infinite")
    func latencyAscendingDefault() {
        let devices = [
            makeDevice(customName: "NoLatency", lastLatency: nil),
            makeDevice(customName: "Fast", lastLatency: 5.0)
        ]
        let result = DeviceList.rows(devices, search: "", onlineOnly: false, sort: .latency, ascending: true)
        #expect(result.map(\.displayName) == ["Fast", "NoLatency"])
    }

    @Test("latency sorts descending when ascending is false")
    func latencyDescendingWhenFalse() {
        let devices = [
            makeDevice(customName: "NoLatency", lastLatency: nil),
            makeDevice(customName: "Fast", lastLatency: 5.0)
        ]
        let result = DeviceList.rows(devices, search: "", onlineOnly: false, sort: .latency, ascending: false)
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

// MARK: - recencyLabel

struct DeviceListRecencyLabelTests {

    let now = Date()

    @Test("compact style at 30 seconds")
    func compact30Seconds() {
        let since = now.addingTimeInterval(-30)
        #expect(DeviceList.recencyLabel(since: since, now: now, style: .compact) == "Now")
    }

    @Test("compact style at 5 minutes")
    func compact5Minutes() {
        let since = now.addingTimeInterval(-5 * 60)
        #expect(DeviceList.recencyLabel(since: since, now: now, style: .compact) == "5m")
    }

    @Test("compact style at 3 hours")
    func compact3Hours() {
        let since = now.addingTimeInterval(-3 * 3600)
        #expect(DeviceList.recencyLabel(since: since, now: now, style: .compact) == "3h")
    }

    @Test("compact style at 2 days")
    func compact2Days() {
        let since = now.addingTimeInterval(-2 * 86400)
        #expect(DeviceList.recencyLabel(since: since, now: now, style: .compact) == "2d")
    }

    @Test("long style at 30 seconds")
    func long30Seconds() {
        let since = now.addingTimeInterval(-30)
        #expect(DeviceList.recencyLabel(since: since, now: now, style: .long) == "Just now")
    }

    @Test("long style at 5 minutes")
    func long5Minutes() {
        let since = now.addingTimeInterval(-5 * 60)
        #expect(DeviceList.recencyLabel(since: since, now: now, style: .long) == "5 minutes ago")
    }

    @Test("long style at 3 hours")
    func long3Hours() {
        let since = now.addingTimeInterval(-3 * 3600)
        #expect(DeviceList.recencyLabel(since: since, now: now, style: .long) == "3 hours ago")
    }

    @Test("long style at 2 days")
    func long2Days() {
        let since = now.addingTimeInterval(-2 * 86400)
        #expect(DeviceList.recencyLabel(since: since, now: now, style: .long) == "2 days ago")
    }
}
