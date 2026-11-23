import Foundation

/// The Timeline's date-range presets on both apps (#491 D6). Each bounded range is whole
/// calendar days in the given calendar's time zone, ending at the start of tomorrow.
public enum TimelineRange: String, CaseIterable, Identifiable, Sendable {
    case today
    case sevenDays
    case thirtyDays
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: "Today"
        case .sevenDays: "7 Days"
        case .thirtyDays: "30 Days"
        case .all: "All"
        }
    }

    /// The calendar days the range covers, today included; nil for `.all`. Day starts come from
    /// `calendar`, so a 23- or 25-hour DST day, or one whose midnight doesn't exist, is still
    /// exactly one day.
    public func bounds(now: Date, calendar: Calendar) -> DateInterval? {
        let days: Int
        switch self {
        case .today: days = 1
        case .sevenDays: days = 7
        case .thirtyDays: days = 30
        case .all: return nil
        }
        guard let today = calendar.dateInterval(of: .day, for: now),
              let first = calendar.date(byAdding: .day, value: 1 - days, to: today.start)
        else { return nil }
        return DateInterval(start: calendar.startOfDay(for: first), end: today.end)
    }
}

/// One calendar day of Timeline events, labelled "Today", "Yesterday" or the medium date.
public struct TimelineDayGroup: Sendable {
    /// The day's start in the grouping calendar.
    public let day: Date
    public let label: String
    /// Newest first.
    public let events: [NetworkEvent]

    /// Groups `events` by calendar day, newest day first and newest event first within a day
    /// (#491 S3). One sort plus one pass: the calendar is asked only once per day, so 20,000
    /// events group in milliseconds.
    public static func groups(_ events: [NetworkEvent], now: Date, calendar: Calendar) -> [TimelineDayGroup] {
        let sorted = events.sorted { $0.timestamp > $1.timestamp }
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today).map { calendar.startOfDay(for: $0) }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        var groups: [TimelineDayGroup] = []
        var day = Date.distantFuture
        var current: [NetworkEvent] = []
        func close() {
            guard !current.isEmpty else { return }
            let label = day == today ? "Today" : day == yesterday ? "Yesterday" : formatter.string(from: day)
            groups.append(TimelineDayGroup(day: day, label: label, events: current))
        }
        for event in sorted {
            if event.timestamp < day {
                close()
                day = calendar.startOfDay(for: event.timestamp)
                current = []
            }
            current.append(event)
        }
        close()
        return groups
    }
}
