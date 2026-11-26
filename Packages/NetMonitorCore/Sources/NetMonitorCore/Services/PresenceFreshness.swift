import Foundation

/// What a saved device row's status means now (#583): an old status never reads as "online now".
/// The app computes it here, in one place, from the row's saved status and the last scan of the
/// row's network (`ScanHistory.lastScanTime(for:)`, on the clock that stamps `lastSeen`). Derived,
/// never stored.
///
/// - **Not checked recently:** the network has no scan, or its last scan is older than the grace
///   interval (or dated more than `clockSkewAllowance` ahead of now), whatever the saved status says.
/// - **Offline:** the saved row was marked offline under `DeviceGracePolicy`.
/// - **Online:** otherwise. A row that missed the latest scan but is still within grace reads
///   Online (lead decision on #583: grace stops phones and sleeping laptops flapping); views always
///   show its real last-seen time next to it, never anything that implies "now".
public enum PresenceFreshness: String, CaseIterable, Sendable, Equatable {
    case online
    case notCheckedRecently
    case offline

    /// Days a device goes unseen, while its network is scanned, before it counts as a past device
    /// and is hidden by default (as eero and Firewalla do).
    public static let pastDeviceDays = 7
    public static let pastDeviceAge = TimeInterval(pastDeviceDays) * 86400
    /// How far ahead of now a scan may be dated (clocks disagree) and still count as recent. A scan
    /// further ahead is a wrong clock, not a recent check.
    public static let clockSkewAllowance: TimeInterval = 5 * 60

    /// The state of a row with `status` on a network last scanned at `lastScan`.
    public static func of(status: DeviceStatus, lastScan: Date?, now: Date, policy: DeviceGracePolicy = DeviceGracePolicy()) -> PresenceFreshness {
        guard isRecent(lastScan, now: now, policy: policy) else { return .notCheckedRecently }
        return status == .offline ? .offline : .online
    }

    /// Whether a network last scanned at `lastScan` counts as checked recently.
    public static func isRecent(_ lastScan: Date?, now: Date, policy: DeviceGracePolicy = DeviceGracePolicy()) -> Bool {
        guard let lastScan else { return false }
        let age = now.timeIntervalSince(lastScan)
        return age >= -clockSkewAllowance && age <= policy.interval
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

    /// The app's one status wording (#583, #585): "Online · Last seen 5 min ago", with the source
    /// after the state when it isn't this device's own ("Online · from your Mac · Last seen …").
    public static func statusText(_ state: PresenceFreshness, lastSeen: Date?, now: Date, source: String? = nil) -> String {
        ([state.label, source] + [lastSeen.map { lastSeenText(since: $0, now: now) }]).compactMap { $0 }.joined(separator: " · ")
    }

    /// "Online, last seen 5 min ago" (or "Online, from your Mac, last seen …"), for VoiceOver.
    public static func accessibilityText(_ state: PresenceFreshness, lastSeen: Date?, now: Date, source: String? = nil) -> String {
        ([state.label, source] + [lastSeen.map { "last seen \(relativeText(since: $0, now: now))" }]).compactMap { $0 }
            .joined(separator: ", ")
    }

    /// The app's one relative-time wording: "just now", "5 min ago", "3 hours ago", "2 days ago".
    /// Safe for any interval: a non-finite one reads "just now", a vast one a capped number of days.
    public static func relativeText(since date: Date, now: Date) -> String {
        let interval = now.timeIntervalSince(date)
        let seconds = interval.isFinite ? min(max(0, interval), 1e12) : 0
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

    /// Whether the network was checked recently: its last scan is within the grace interval.
    public func isNetworkChecked(_ network: UUID?) -> Bool {
        PresenceFreshness.isRecent(lastScan(for: network), now: now, policy: policy)
    }

    public func freshness(of device: LocalDevice) -> PresenceFreshness {
        PresenceFreshness.of(status: device.status, lastScan: lastScan(for: device.networkProfileID), now: now, policy: policy)
    }

    /// Whether the device answered its network's latest scan, and that scan is recent: a sighting,
    /// as the companion feed reports one (#583, #598). Stricter than `.online`: a row within grace
    /// that missed the scan, or one only the ARP cache listed, didn't answer.
    public func answeredLatestScan(_ device: LocalDevice) -> Bool {
        guard isNetworkChecked(device.networkProfileID), device.status == .online,
              let lastScan = lastScan(for: device.networkProfileID) else { return false }
        return device.lastSeen >= lastScan
    }

    /// The device's last latency, only while it is online: an old one is no news (#583).
    public func currentLatency(_ device: LocalDevice) -> Double? {
        freshness(of: device).isOnline ? device.lastLatency : nil
    }

    public func isPast(_ device: LocalDevice) -> Bool {
        PresenceFreshness.isPast(lastSeen: device.lastSeen, lastScan: lastScan(for: device.networkProfileID), now: now)
    }

    /// "Last seen 5 min ago".
    public func lastSeenText(_ device: LocalDevice) -> String {
        PresenceFreshness.lastSeenText(since: device.lastSeen, now: now)
    }

    /// "5 min ago", for compact rows.
    public func relativeLastSeen(_ device: LocalDevice) -> String {
        PresenceFreshness.relativeText(since: device.lastSeen, now: now)
    }

    /// "Online · Last seen 5 min ago": the visible status line.
    public func statusText(_ device: LocalDevice) -> String {
        PresenceFreshness.statusText(freshness(of: device), lastSeen: device.lastSeen, now: now)
    }

    /// "Online, last seen 5 min ago": what VoiceOver says for a row's presence, once.
    public func accessibilityText(_ device: LocalDevice) -> String {
        PresenceFreshness.accessibilityText(freshness(of: device), lastSeen: device.lastSeen, now: now)
    }
}
