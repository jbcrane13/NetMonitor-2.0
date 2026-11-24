import Foundation

/// A saved device as "Ask your network" sees it (#452), read through the identity seam and keyed
/// by `LocalDevice.id`.
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

    public init(
        id: UUID, displayName: String, deviceType: DeviceType, maker: String?, ipAddress: String,
        status: DeviceStatus, lastSeen: Date, lastLatency: Double?, latencyHistory: [Double]
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
    }

    /// A saved device as Ask sees it. The maker leaves out model suggestions.
    public init(_ device: LocalDevice) {
        self.init(
            id: device.id, displayName: device.displayName, deviceType: device.deviceType,
            maker: device.makerExcludingSuggestions, ipAddress: device.ipAddress, status: device.status,
            lastSeen: device.lastSeen, lastLatency: device.lastLatency, latencyHistory: device.latencyHistory
        )
    }
}

/// What the app holds when a question is asked (#452): the current network's saved devices and
/// its Timeline events. The tools answer from this copy only, so nothing is measured.
public struct AskSnapshot: Sendable {
    public let devices: [AskDevice]
    /// Newest first.
    public let events: [NetworkEvent]
    public let now: Date
    public let calendar: Calendar

    /// - Parameter networkProfileID: keeps the events of this network and those written before
    ///   events carried one. Devices are filtered by the caller.
    public init(devices: [AskDevice], events: [NetworkEvent], networkProfileID: UUID? = nil, now: Date, calendar: Calendar = .current) {
        self.devices = devices
        self.events = events
            .filter { networkProfileID == nil || $0.networkProfileID == nil || $0.networkProfileID == networkProfileID }
            .sorted { $0.timestamp > $1.timestamp }
        self.now = now
        self.calendar = calendar
    }

    /// "2026-11-23 9:14 AM" in the snapshot's calendar: the form the model is asked to copy.
    func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd h:mm a"
        return formatter.string(from: date)
    }

    /// "2026-11-23", in the snapshot's calendar.
    func formatDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
