import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData

/// The devices the iPhone's device list and dashboard card show (#583): the network's saved rows,
/// each with its `PresenceFreshness` and last-seen time, plus the live scan's devices not saved yet
/// ("Found in this scan"), so a scan in progress, or a stopped one, still shows what it found.
/// Sorted and filtered by presence; past devices left out unless shown.
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
        /// A saved device, shown with its presence.
        case saved(LocalDevice)
        /// A device this scan found that has no saved row yet. It answered, so it is online.
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
    ///   - saved: saved rows; those of `network` (or of none) are listed.
    ///   - live: the scan's devices, during or after it; those matching a saved row (by MAC, else
    ///     address) are that row, the rest are listed as found in this scan.
    init(saved: [LocalDevice], live: [DiscoveredDevice] = [], network: UUID?, sort: Sort, showPast: Bool, presence: PresenceSnapshot) {
        let rows = saved.filter { $0.networkProfileID == network || $0.networkProfileID == nil }
        self.presence = presence
        let found = live.filter { device in
            (device.networkProfileID == network || device.networkProfileID == nil) && !rows.contains { Self.matches($0, device) }
        }
        let shown = DeviceList.rows(rows, filter: DeviceListFilter(showPast: showPast), presence: presence, sort: .ipAddress, ascending: true)
        pastCount = DeviceList.pastCount(rows, search: "", presence: presence)
        entries = Self.sorted(shown.map(Entry.saved) + found.map(Entry.found), by: sort, presence: presence)
    }

    /// The saved rows the list reads: the network's and those saved without one, most recently seen
    /// first, at most `fetchLimit`.
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

    /// Rows online now, counting devices found in this scan.
    var onlineCount: Int {
        entries.count { entry in
            if case .saved(let device) = entry {
                return presence.freshness(of: device).isOnline
            }
            return true
        }
    }

    /// The last latency, only while the device is online: an old one is no news.
    func latencyText(_ device: LocalDevice) -> String? {
        guard presence.freshness(of: device).isOnline, let latency = device.lastLatency else { return nil }
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
        if case .saved(let device) = entry {
            return presence.freshness(of: device)
        }
        return .online
    }

    private static func latency(_ entry: Entry, _ presence: PresenceSnapshot) -> Double {
        switch entry {
        case .saved(let device): presence.freshness(of: device).isOnline ? device.lastLatency ?? .infinity : .infinity
        case .found(let device): device.latency ?? .infinity
        }
    }
}
