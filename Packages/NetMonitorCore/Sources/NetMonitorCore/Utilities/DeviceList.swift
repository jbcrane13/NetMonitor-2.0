import Foundation

/// Sort keys for a device list. `lastSeen` sorts descending by default; every
/// other case sorts ascending by default (see `DeviceList.rows`).
public enum DeviceSortOrder: String, CaseIterable, Sendable {
    case lastSeen
    case name
    case ipAddress
    case status
    case vendor
    case latency
}

/// What a device list shows (#583): a search, whether only online devices show, and whether past
/// devices do.
public struct DeviceListFilter: Sendable, Equatable {
    public var search: String
    public var onlineOnly: Bool
    public var showPast: Bool

    public init(search: String = "", onlineOnly: Bool = false, showPast: Bool = false) {
        self.search = search
        self.onlineOnly = onlineOnly
        self.showPast = showPast
    }
}

/// Pure derivation of a device list's search, filter and sort, shared by every device list (both
/// platforms). It works on devices, not rows (#594): rows are projected first
/// (`DeviceGroups.project`), so a group of interfaces is one entry; then searched, filtered and
/// sorted. Pass complete groups (`DeviceGroups.completingGroups`).
public enum DeviceList {
    /// The devices of `rows` per `filter`, `sort`, and `ascending`.
    ///
    /// `onlineOnly` and the `status` sort use each device's `PresenceFreshness` from `presence` (the
    /// best member's), never a saved status alone (#583); the status sort is online, then not
    /// checked recently, then offline. Past devices (`PresenceFreshness.isPast`, on the latest
    /// member's last seen) are left out unless `showPast`.
    ///
    /// The search matches (case-insensitively, except IP address which uses `contains`) the
    /// device's name and every member's name, IP address, MAC address and maker.
    ///
    /// `lastSeen` sorts descending (most recent first) by default; every other sort
    /// sorts ascending by default. `ascending` inverts that default: for `lastSeen`,
    /// passing `true` reverses to ascending; for every other sort, passing `false`
    /// reverses to descending. Addresses and latency are the current member's.
    public static func devices(
        _ rows: [LocalDevice], filter: DeviceListFilter, presence: PresenceSnapshot, sort: DeviceSortOrder, ascending: Bool
    ) -> [DeviceProjection] {
        var result = matching(DeviceGroups.project(rows), search: filter.search)

        if filter.onlineOnly {
            result = result.filter { presence.freshness(of: $0).isOnline }
        }

        if !filter.showPast {
            result = result.filter { !presence.isPast($0) }
        }

        switch sort {
        case .lastSeen:
            result.sort { $0.lastSeen > $1.lastSeen }
        case .name:
            result.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .ipAddress:
            result.sort { compareIPAddresses($0.ipAddress, $1.ipAddress) }
        case .status:
            result.sort { statusRank(presence.freshness(of: $0)) < statusRank(presence.freshness(of: $1)) }
        case .vendor:
            result.sort { (maker(of: $0) ?? "zzz").localizedCaseInsensitiveCompare(maker(of: $1) ?? "zzz") == .orderedAscending }
        case .latency:
            result.sort { ($0.current.lastLatency ?? .infinity) < ($1.current.lastLatency ?? .infinity) }
        }

        // Reverse for descending (lastSeen defaults descending, so invert logic)
        if sort == .lastSeen ? ascending : !ascending {
            result.reverse()
        }

        return result
    }

    /// How many past devices showing them would add under `filter`'s search and Online Only: the
    /// N in "Show past devices (N)". With Online Only on, an offline past device adds nothing.
    public static func pastCount(_ rows: [LocalDevice], filter: DeviceListFilter, presence: PresenceSnapshot) -> Int {
        matching(DeviceGroups.project(rows), search: filter.search).count { device in
            presence.isPast(device) && (!filter.onlineOnly || presence.freshness(of: device).isOnline)
        }
    }

    /// The device's maker: the primary's, else the first member's that has one.
    static func maker(of device: DeviceProjection) -> String? {
        device.primary.maker ?? device.members.lazy.compactMap(\.maker).first
    }

    private static func matching(_ devices: [DeviceProjection], search: String) -> [DeviceProjection] {
        guard !search.isEmpty else { return devices }
        return devices.filter { device in
            device.displayName.localizedCaseInsensitiveContains(search) || device.members.contains { member in
                member.displayName.localizedCaseInsensitiveContains(search) ||
                    member.ipAddress.contains(search) ||
                    member.macAddress.localizedCaseInsensitiveContains(search) ||
                    (member.maker?.localizedCaseInsensitiveContains(search) ?? false)
            }
        }
    }

    private static func statusRank(_ freshness: PresenceFreshness) -> Int {
        switch freshness {
        case .online: 0
        case .notCheckedRecently: 1
        case .offline: 2
        }
    }

    /// Compares two dotted-quad IP address strings numerically per octet
    /// (e.g. `192.168.2.3 < 192.168.2.10`).
    public static func compareIPAddresses(_ lhs: String, _ rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: ".").compactMap { Int($0) }
        let rhsParts = rhs.split(separator: ".").compactMap { Int($0) }
        for index in 0..<min(lhsParts.count, rhsParts.count) where lhsParts[index] != rhsParts[index] {
            return lhsParts[index] < rhsParts[index]
        }
        return lhsParts.count < rhsParts.count
    }
}
