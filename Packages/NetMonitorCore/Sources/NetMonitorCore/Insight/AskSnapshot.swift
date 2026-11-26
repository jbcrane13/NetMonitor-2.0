import Foundation

/// A saved device as "Ask your network" sees it (#452), read through the identity seam and keyed
/// by `LocalDevice.id` (a group's primary's, #594; any member's ID finds it).
public struct AskDevice: DevicePhraseMatchable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let displayName: String
    public let deviceType: DeviceType
    public let maker: String?
    public let ipAddress: String
    public let status: DeviceStatus
    public let lastSeen: Date
    public let lastLatency: Double?
    /// This session's latency samples, oldest first (`LocalDevice.latencyHistory`). Only replies
    /// are recorded, so a lost ping leaves no sample.
    public let latencyHistory: [Double]
    /// Every interface's address, the current one (`ipAddress`) first (#594).
    public let addresses: [String]
    /// Every member row's ID: events and citations may name any of them (#594).
    public let memberIDs: [UUID]

    public init(
        id: UUID, displayName: String, deviceType: DeviceType, maker: String?, ipAddress: String,
        status: DeviceStatus, lastSeen: Date, lastLatency: Double?, latencyHistory: [Double],
        addresses: [String]? = nil, memberIDs: [UUID]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.deviceType = deviceType
        self.maker = maker
        self.ipAddress = ipAddress
        self.status = status
        self.lastSeen = lastSeen
        self.lastLatency = lastLatency
        self.latencyHistory = latencyHistory
        self.addresses = addresses ?? [ipAddress]
        self.memberIDs = memberIDs ?? [id]
    }

    /// A saved device as Ask sees it (#594: a device, not a row): the primary's identity, the
    /// current member's address, latency and samples, the best member's saved status and the
    /// latest last seen. The maker leaves out model suggestions.
    public init(_ device: DeviceProjection) {
        let primary = device.primary, current = device.current
        let statuses = device.members.map(\.status)
        let status: DeviceStatus = statuses.contains(.online) ? .online : statuses.contains(.cached) ? .cached : primary.status
        self.init(
            id: primary.id, displayName: device.displayName, deviceType: primary.deviceType,
            maker: primary.makerExcludingSuggestions, ipAddress: current.ipAddress, status: status,
            lastSeen: device.lastSeen, lastLatency: current.lastLatency, latencyHistory: current.latencyHistory,
            addresses: device.members.map(\.ipAddress), memberIDs: device.members.map(\.id)
        )
    }

    /// "192.168.1.10", or "192.168.1.10 and 192.168.1.40" for a device with two interfaces.
    public var addressText: String {
        ListFormatter.localizedString(byJoining: addresses)
    }
}

/// What the app holds when a question is asked (#452): the current network's saved devices, its
/// Timeline events and when it was last scanned. The tools answer from this copy only, so nothing
/// is measured.
///
/// A saved status is only as fresh as the scan that set it (Blake, 2026-11-24: never let an old
/// status read as "online now"). The app works out how fresh: "as of the scan N minutes ago" while
/// the last scan is within `staleAfter` (the grace interval), "not checked recently" after it.
public struct AskSnapshot: Sendable {
    /// How recent the network's last scan is.
    public enum ScanFreshness: Equatable, Sendable {
        case notScanned
        case fresh
        case stale
    }

    public let devices: [AskDevice]
    /// The network asked about; the live tools ping only while this device is on it (#579).
    public let networkProfileID: UUID?
    /// Newest first.
    public let events: [NetworkEvent]
    /// When the network's last scan finished, on the clock that stamps `lastSeen`; nil when it
    /// has none.
    public let lastScan: Date?
    /// After this long the last scan is "not checked recently".
    public let staleAfter: TimeInterval
    public let now: Date
    public let calendar: Calendar
    /// Made once per snapshot, in its calendar, for every time the tools and instructions write.
    private let formatters: Formatters

    /// The date formatters a snapshot writes with. `DateFormatter` is thread-safe for formatting.
    private final class Formatters: @unchecked Sendable {
        let time: DateFormatter
        let day: DateFormatter
        let weekday: DateFormatter

        init(calendar: Calendar) {
            func make(_ format: String) -> DateFormatter {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = format
                return formatter
            }
            time = make("yyyy-MM-dd h:mm a")
            day = make("yyyy-MM-dd")
            weekday = make("EEEE, yyyy-MM-dd")
        }
    }

    /// The saved devices Ask reads for `network`: its own and those saved before rows had one, each
    /// group of interfaces one device (#594). The one place the apps and the Siri intent filter
    /// devices by network. Pass complete groups.
    @MainActor
    public static func devices(_ rows: [LocalDevice], on network: UUID?) -> [AskDevice] {
        DeviceGroups.project(rows.filter { $0.networkProfileID == nil || $0.networkProfileID == network }).map(AskDevice.init)
    }

    /// - Parameter networkProfileID: keeps the events of this network and those written before
    ///   events carried one. Devices are filtered by the caller (`devices(_:on:)`).
    public init(
        devices: [AskDevice],
        events: [NetworkEvent],
        networkProfileID: UUID? = nil,
        lastScan: Date?,
        staleAfter: TimeInterval = DeviceGracePolicy().interval,
        now: Date,
        calendar: Calendar = .current
    ) {
        self.devices = devices
        self.networkProfileID = networkProfileID
        self.events = events
            .filter { networkProfileID == nil || $0.networkProfileID == nil || $0.networkProfileID == networkProfileID }
            .sorted { $0.timestamp > $1.timestamp }
        self.lastScan = lastScan
        self.staleAfter = staleAfter
        self.now = now
        self.calendar = calendar
        formatters = Formatters(calendar: calendar)
    }

    public var scanFreshness: ScanFreshness {
        guard let lastScan else { return .notScanned }
        // The same rule as every device's presence (#583), clock skew included.
        return PresenceFreshness.isRecent(lastScan, now: now, policy: DeviceGracePolicy(interval: staleAfter)) ? .fresh : .stale
    }

    /// The app's line on how fresh device statuses are, shown under an answer word for word.
    public var freshnessNote: String {
        guard let lastScan else {
            return "This network hasn't been scanned yet, so no device's status has been checked."
        }
        switch scanFreshness {
        case .stale: return "Not checked recently: the last scan was \(ago(lastScan)) (\(format(lastScan)))."
        default: return "Device status as of the scan \(ago(lastScan)) (\(format(lastScan)))."
        }
    }

    /// "less than a minute ago", "40 minutes ago", "2 hours ago", "3 days ago": one unit, rounded
    /// down, so the model has one form to repeat.
    func ago(_ date: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        func count(_ value: Int, _ unit: String) -> String {
            "\(value) \(unit)\(value == 1 ? "" : "s") ago"
        }
        switch seconds {
        case ..<60: return "less than a minute ago"
        case ..<3600: return count(Int(seconds / 60), "minute")
        case ..<86400: return count(Int(seconds / 3600), "hour")
        default: return count(Int(seconds / 86400), "day")
        }
    }

    /// "2026-11-23 9:14 AM" in the snapshot's calendar: the form the model is asked to copy.
    func format(_ date: Date) -> String {
        formatters.time.string(from: date)
    }

    /// "2026-11-23", in the snapshot's calendar.
    func formatDay(_ date: Date) -> String {
        formatters.day.string(from: date)
    }

    /// "Monday, 2026-11-23", for the model's instructions.
    func formatWeekday(_ date: Date) -> String {
        formatters.weekday.string(from: date)
    }
}

/// The time ranges the event tools take. The model picks one by name; the app works out the days.
public enum AskRange: String, CaseIterable, Sendable {
    // The default first: listed after today, the model chose today for "which devices have been flaky?".
    case last7Days
    case today
    case yesterday
    case last30Days

    /// The range a tool argument names, or the last 7 days for anything else.
    static func named(_ text: String) -> AskRange {
        AskRange(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .last7Days
    }

    /// The calendar days the range covers, today included for all but yesterday.
    func interval(now: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        func daysBack(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: today) ?? today
        }
        switch self {
        case .today: return DateInterval(start: today, end: todayEnd)
        case .yesterday: return DateInterval(start: daysBack(1), end: today)
        case .last7Days: return DateInterval(start: daysBack(6), end: todayEnd)
        case .last30Days: return DateInterval(start: daysBack(29), end: todayEnd)
        }
    }

    /// "today (2026-11-23)" or "in the last 7 days (2026-11-17 to 2026-11-23)", to follow a noun.
    func label(in snapshot: AskSnapshot) -> String {
        let interval = interval(now: snapshot.now, calendar: snapshot.calendar)
        let first = snapshot.formatDay(interval.start)
        let last = snapshot.formatDay(interval.end.addingTimeInterval(-1))
        switch self {
        case .today: return "today (\(first))"
        case .yesterday: return "yesterday (\(first))"
        case .last7Days: return "in the last 7 days (\(first) to \(last))"
        case .last30Days: return "in the last 30 days (\(first) to \(last))"
        }
    }
}
