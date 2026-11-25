import Foundation

/// What a saved device row's status means now (#583): an old status never reads as "online now".
/// The app computes it here, in one place, from the row and the last scan of the row's network
/// (`ScanHistory.lastScanTime(for:)`, on the clock that stamps `lastSeen`). Derived, never stored.
///
/// - **Not checked recently:** the network has no scan, or its last scan is older than the grace
///   interval, whatever the saved status says.
/// - **Offline:** the saved row was marked offline under `DeviceGracePolicy`.
/// - **Online:** otherwise. A row that missed the latest scan but is still within grace reads
///   Online (lead decision on #583: grace stops phones and sleeping laptops flapping); views always
///   show its real last-seen time next to it, never anything that implies "now".
public enum PresenceFreshness: String, CaseIterable, Sendable, Equatable {
    case online
    case notCheckedRecently
    case offline

    /// How long a device goes unseen, while its network is scanned, before it counts as a past
    /// device and is hidden by default (as eero and Firewalla do).
    public static let pastDeviceAge: TimeInterval = 7 * 86400

    public static func of(
        status: DeviceStatus, lastSeen: Date, lastScan: Date?, now: Date, policy: DeviceGracePolicy = DeviceGracePolicy()
    ) -> PresenceFreshness {
        // A scan dated ahead of now (clock skew) is as recent as one taken now.
        guard let lastScan, now.timeIntervalSince(lastScan) <= policy.interval else { return .notCheckedRecently }
        return status == .offline ? .offline : .online
    }

    public var isOnline: Bool { self == .online }

    /// The state's own text, so it never relies on colour alone.
    public var label: String {
        switch self {
        case .online: "Online"
        case .notCheckedRecently: "Not checked recently"
        case .offline: "Offline"
        }
    }

    /// Whether a row is a past device: unseen for `pastDeviceAge` before its network's last scan,
    /// so not scanning for a week hides nothing new. Without a scan, age counts to `now`.
    public static func isPast(lastSeen: Date, lastScan: Date?, now: Date) -> Bool {
        (lastScan ?? now).timeIntervalSince(lastSeen) >= pastDeviceAge
    }

    /// "Last seen 5 min ago", "Last seen 2 days ago". A time ahead of `now` reads "just now".
    public static func lastSeenText(since lastSeen: Date, now: Date) -> String {
        "Last seen \(relativeText(since: lastSeen, now: now))"
    }

    /// "just now", "5 min ago", "3 hours ago", "2 days ago".
    public static func relativeText(since date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 {
            return "just now"
        }
        if seconds < 3600 {
            return "\(Int(seconds / 60)) min ago"
        }
        if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        let days = Int(seconds / 86400)
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }
}

/// The last scan of each network a list shows, read once, and the time it is read at: what a
/// device list needs to show every row's `PresenceFreshness` (#583).
public struct PresenceSnapshot: Sendable, Equatable {
    public let now: Date
    public let policy: DeviceGracePolicy
    private let lastScans: [UUID?: Date]

    public init(lastScans: [UUID?: Date], now: Date, policy: DeviceGracePolicy = DeviceGracePolicy()) {
        self.lastScans = lastScans
        self.now = now
        self.policy = policy
    }

    /// When the network's last scan was reconciled; nil when it has none.
    public func lastScan(for network: UUID?) -> Date? {
        lastScans[network]
    }

    public func freshness(of device: LocalDevice) -> PresenceFreshness {
        PresenceFreshness.of(
            status: device.status, lastSeen: device.lastSeen, lastScan: lastScan(for: device.networkProfileID), now: now, policy: policy
        )
    }

    public func isPast(_ device: LocalDevice) -> Bool {
        PresenceFreshness.isPast(lastSeen: device.lastSeen, lastScan: lastScan(for: device.networkProfileID), now: now)
    }

    /// "Last seen 5 min ago".
    public func lastSeenText(_ device: LocalDevice) -> String {
        PresenceFreshness.lastSeenText(since: device.lastSeen, now: now)
    }
}
