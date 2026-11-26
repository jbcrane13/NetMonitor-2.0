import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData

/// The devices the iPhone's device list and dashboard card show (#583): the network's saved
/// devices, each with its `PresenceFreshness` and last-seen time, plus the live scan's devices not
/// saved yet ("Found in this scan"), so a scan in progress, or a stopped one, still shows what it
/// found. Sorted and filtered by presence; past devices left out unless shown. A group of rows that
/// are one device's interfaces is one entry (#594): projected first, then filtered and sorted.
@MainActor
struct SavedDeviceList {
    /// How the list sorts; online first for `.status`, then not checked recently, then offline.
    enum Sort: String, CaseIterable {
        case ip = "IP Address"
        case name = "Name"
        case latency = "Latency"
        case status = "Status"
    }

    /// A row of the list.
    enum Entry: Identifiable {
        /// A saved device (a row, or a group of interfaces), shown with its presence.
        case saved(DeviceProjection)
        /// A device a scan found that has no saved row yet: online only while that sighting is recent.
        case found(DiscoveredDevice)

        var id: String {
            switch self {
            case .saved(let device): "saved-\(device.id)"
            case .found(let device): "found-\(device.id)"
            }
        }

        var ipAddress: String {
            switch self {
            case .saved(let device): device.ipAddress
            case .found(let device): device.ipAddress
            }
        }

        /// Where tapping the row goes: a saved device by its ID (#584; a group's own ID, #594), so
        /// an address DHCP gave another device never opens the wrong one; a found device by its
        /// address.
        var destination: AppDestination {
            switch self {
            case .saved(let device): .savedDevice(id: device.id)
            case .found(let device):
                .deviceDetail(ipAddress: device.ipAddress, networkID: device.networkProfileID, macAddress: device.macAddress)
            }
        }

        var displayName: String {
            switch self {
            case .saved(let device): device.displayName
            case .found(let device): device.displayName
            }
        }
    }

    let entries: [Entry]
    /// The N in "Show past devices (N)".
    let pastCount: Int
    let presence: PresenceSnapshot

    /// - Parameters:
    ///   - saved: saved rows, complete groups (``completing(_:with:)``); those of `network` (or of
    ///     none) are listed, one entry per device.
    ///   - live: the scan's devices, during or after it; those matching a saved row (by MAC, else
    ///     address) are that row's device, the rest are listed as found in this scan.
    init(saved: [LocalDevice], live: [DiscoveredDevice] = [], network: UUID?, sort: Sort, showPast: Bool, presence: PresenceSnapshot) {
        let rows = saved.filter { $0.networkProfileID == network || $0.networkProfileID == nil }
        self.presence = presence
        let found = live.filter { device in
            (device.networkProfileID == network || device.networkProfileID == nil) && !rows.contains { Self.matches($0, device) }
        }
        let shown = DeviceList.devices(rows, filter: DeviceListFilter(showPast: showPast), presence: presence, sort: .ipAddress, ascending: true)
        pastCount = DeviceList.pastCount(rows, filter: DeviceListFilter(), presence: presence)
        entries = Self.sorted(shown.map(Entry.saved) + found.map(Entry.found), by: sort, presence: presence)
    }

    /// The saved rows the list reads: the network's and those saved without one, most recently seen
    /// first, at most `fetchLimit`. Complete its groups (``completing(_:with:)`` with
    /// ``groupedDescriptor(network:)``) before listing them (#594).
    static func fetchDescriptor(network: UUID?) -> FetchDescriptor<LocalDevice> {
        var descriptor: FetchDescriptor<LocalDevice>
        if let network {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.networkProfileID == network || $0.networkProfileID == nil })
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.networkProfileID == nil })
        }
        descriptor.sortBy = [SortDescriptor(\.lastSeen, order: .reverse)]
        descriptor.fetchLimit = fetchLimit
        return descriptor
    }

    static let fetchLimit = 500

    /// The grouped rows of the same networks (#594), for ``completing(_:with:)``: a bounded fetch
    /// may hold a group's newest member but not its primary.
    static func groupedDescriptor(network: UUID?) -> FetchDescriptor<LocalDevice> {
        if let network {
            return FetchDescriptor(predicate: #Predicate {
                $0.deviceGroupID != nil && ($0.networkProfileID == network || $0.networkProfileID == nil)
            })
        }
        return FetchDescriptor(predicate: #Predicate { $0.deviceGroupID != nil && $0.networkProfileID == nil })
    }

    /// `rows` plus the members of their groups that `grouped` holds and `rows` doesn't (#594).
    static func completing(_ rows: [LocalDevice], with grouped: [LocalDevice]) -> [LocalDevice] {
        let groupIDs = Set(rows.compactMap(\.deviceGroupID))
        guard !groupIDs.isEmpty else { return rows }
        let have = Set(rows.map(\.id))
        return rows + grouped.filter { row in row.deviceGroupID.map(groupIDs.contains) == true && !have.contains(row.id) }
    }

    /// Devices online now, counting devices found by a recent scan.
    var onlineCount: Int {
        entries.count { Self.freshness($0, presence).isOnline }
    }

    /// A found device is online while its sighting is within the grace interval; a stopped or
    /// cached scan's device goes "not checked recently" like any saved row (#583).
    func freshness(of device: DiscoveredDevice) -> PresenceFreshness {
        PresenceFreshness.isRecent(device.discoveredAt, now: presence.now, policy: presence.policy) ? .online : .notCheckedRecently
    }

    /// "Found in this scan", or "Not checked recently · found 2 hours ago" for an old sighting.
    func foundText(_ device: DiscoveredDevice) -> String {
        guard freshness(of: device) == .notCheckedRecently else { return "Found in this scan" }
        return "\(PresenceFreshness.notCheckedRecently.label) · found \(PresenceFreshness.relativeText(since: device.discoveredAt, now: presence.now))"
    }

    /// The current member's last latency, only while the device is online: an old one is no news.
    func latencyText(_ device: DeviceProjection) -> String? {
        guard let latency = presence.currentLatency(device) else { return nil }
        return latency < 1 ? "<1 ms" : "\(Int(latency.rounded())) ms"
    }

    /// The same device: an identical real MAC, else the same address.
    private static func matches(_ row: LocalDevice, _ device: DiscoveredDevice) -> Bool {
        if let mac = DeviceMatcher.normalizedMAC(device.macAddress), let rowMAC = DeviceMatcher.normalizedMAC(row.macAddress) {
            return mac == rowMAC
        }
        return row.ipAddress == device.ipAddress
    }

    private static func sorted(_ entries: [Entry], by sort: Sort, presence: PresenceSnapshot) -> [Entry] {
        let byIP = entries.sorted { DeviceList.compareIPAddresses($0.ipAddress, $1.ipAddress) }
        switch sort {
        case .ip:
            return byIP
        case .name:
            return byIP.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .latency:
            return byIP.sorted { latency($0, presence) < latency($1, presence) }
        case .status:
            return PresenceFreshness.allCases.flatMap { state in byIP.filter { freshness($0, presence) == state } }
        }
    }

    private static func freshness(_ entry: Entry, _ presence: PresenceSnapshot) -> PresenceFreshness {
        switch entry {
        case .saved(let device):
            presence.freshness(of: device)
        case .found(let device):
            PresenceFreshness.isRecent(device.discoveredAt, now: presence.now, policy: presence.policy) ? .online : .notCheckedRecently
        }
    }

    private static func latency(_ entry: Entry, _ presence: PresenceSnapshot) -> Double {
        switch entry {
        case .saved(let device): presence.currentLatency(device) ?? .infinity
        case .found(let device):
            PresenceFreshness.isRecent(device.discoveredAt, now: presence.now, policy: presence.policy) ? device.latency ?? .infinity : .infinity
        }
    }
}
