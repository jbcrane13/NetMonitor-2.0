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

/// Formatting style for `DeviceList.recencyLabel`.
public enum RecencyStyle: Sendable {
    case compact
    case long
}

/// Pure derivation of a device list's search/filter/sort, and its "last seen"
/// recency label, shared by every macOS device list view.
public enum DeviceList {
    /// Filters and sorts `devices` per `search`, `onlineOnly`, `showPast`, `sort`, and `ascending`.
    ///
    /// `onlineOnly` and the `status` sort use each row's `PresenceFreshness` from `presence`, never
    /// the saved status alone (#583); the status sort is online, then not checked recently, then
    /// offline. Past devices (`PresenceFreshness.isPast`) are left out unless `showPast`.
    ///
    /// `search` matches (case-insensitively, except IP address which uses `contains`)
    /// against displayName, ipAddress, macAddress, and vendor.
    ///
    /// `lastSeen` sorts descending (most recent first) by default; every other sort
    /// sorts ascending by default. `ascending` inverts that default: for `lastSeen`,
    /// passing `true` reverses to ascending; for every other sort, passing `false`
    /// reverses to descending.
    public static func rows( // swiftlint:disable:this function_parameter_count
        _ devices: [LocalDevice],
        search: String,
        onlineOnly: Bool,
        showPast: Bool,
        presence: PresenceSnapshot,
        sort: DeviceSortOrder,
        ascending: Bool
    ) -> [LocalDevice] {
        var result = matching(devices, search: search)

        if onlineOnly {
            result = result.filter { presence.freshness(of: $0).isOnline }
        }

        if !showPast {
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
            result.sort { ($0.maker ?? "zzz").localizedCaseInsensitiveCompare($1.maker ?? "zzz") == .orderedAscending }
        case .latency:
            result.sort { ($0.lastLatency ?? .infinity) < ($1.lastLatency ?? .infinity) }
        }

        // Reverse for descending (lastSeen defaults descending, so invert logic)
        if sort == .lastSeen ? ascending : !ascending {
            result.reverse()
        }

        return result
    }

    /// How many devices matching `search` are past devices, hidden unless shown: the N in
    /// "Show past devices (N)".
    public static func pastCount(_ devices: [LocalDevice], search: String, presence: PresenceSnapshot) -> Int {
        matching(devices, search: search).count { presence.isPast($0) }
    }

    private static func matching(_ devices: [LocalDevice], search: String) -> [LocalDevice] {
        guard !search.isEmpty else { return devices }
        return devices.filter { device in
            device.displayName.localizedCaseInsensitiveContains(search) ||
                device.ipAddress.contains(search) ||
                device.macAddress.localizedCaseInsensitiveContains(search) ||
                (device.maker?.localizedCaseInsensitiveContains(search) ?? false)
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

    /// Formats the time elapsed since `since` (relative to `now`) as a "last seen" label.
    ///
    /// `.compact` yields "Now" / "5m" / "3h" / "2d"; `.long` yields
    /// "Just now" / "5 minutes ago" / "3 hours ago" / "2 days ago".
    /// Thresholds: 60 s, 3600 s, 86400 s.
    public static func recencyLabel(since: Date, now: Date = .now, style: RecencyStyle) -> String {
        let interval = now.timeIntervalSince(since)
        switch style {
        case .compact:
            if interval < 60 {
                return "Now"
            }
            if interval < 3600 {
                return "\(Int(interval / 60))m"
            }
            if interval < 86400 {
                return "\(Int(interval / 3600))h"
            }
            return "\(Int(interval / 86400))d"
        case .long:
            if interval < 60 {
                return "Just now"
            }
            if interval < 3600 {
                return "\(Int(interval / 60)) minutes ago"
            }
            if interval < 86400 {
                return "\(Int(interval / 3600)) hours ago"
            }
            return "\(Int(interval / 86400)) days ago"
        }
    }
}
