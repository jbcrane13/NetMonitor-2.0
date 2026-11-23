import Foundation
import Testing
@testable import NetMonitorCore

@Suite("TimelineDayGroup (#491 S3)")
struct TimelineDayGroupTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        // swiftlint:disable:next force_unwrapping
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func event(_ title: String, _ timestamp: Date) -> NetworkEvent {
        NetworkEvent(type: .deviceJoined, timestamp: timestamp, title: title)
    }

    @Test("Days are newest first by date, not by label text")
    func chronologicalOrder() {
        let now = date(2027, 1, 5)
        // Alphabetically "Nov 5, 2026" > "Jan 2, 2027" > "Dec 30, 2026", which is the old, wrong order.
        let events = [
            event("dec", date(2026, 12, 30)), event("nov", date(2026, 11, 5)),
            event("today", date(2027, 1, 5, 9)), event("jan", date(2027, 1, 2)),
            event("yesterday", date(2027, 1, 4))
        ]
        let groups = TimelineDayGroup.groups(events, now: now, calendar: calendar)
        #expect(groups.map(\.label) == ["Today", "Yesterday", "Jan 2, 2027", "Dec 30, 2026", "Nov 5, 2026"])
        #expect(groups.map { $0.events.map(\.title) } == [["today"], ["yesterday"], ["jan"], ["dec"], ["nov"]])
        #expect(groups[2].day == date(2027, 1, 2, 0))
    }

    @Test("Events within a day are newest first, whatever order they arrive in")
    func newestFirstWithinADay() {
        let now = date(2026, 6, 1, 20)
        let events = [event("noon", date(2026, 6, 1, 12)), event("evening", date(2026, 6, 1, 19)), event("morning", date(2026, 6, 1, 8))]
        let groups = TimelineDayGroup.groups(events, now: now, calendar: calendar)
        #expect(groups.count == 1)
        #expect(groups[0].events.map(\.title) == ["evening", "noon", "morning"])
    }

    @Test("An event at 00:30 on a fall-back day and one at 23:30 share the day")
    func dstDayIsOneGroup() {
        let now = date(2026, 11, 2)
        let events = [event("late", date(2026, 11, 1, 23)), event("early", date(2026, 11, 1, 0))]
        let groups = TimelineDayGroup.groups(events, now: now, calendar: calendar)
        #expect(groups.map(\.label) == ["Yesterday"])
        #expect(groups[0].events.count == 2)
    }

    @Test("20,000 events across 90 days group within the bound")
    func twentyThousandEvents() {
        let now = date(2026, 6, 1, 23)
        let events = (0 ..< 20_000).map { index in
            event("e\(index)", now.addingTimeInterval(-Double(index) * 90 * 86400 / 20_000))
        }
        let clock = ContinuousClock()
        var groups: [TimelineDayGroup] = []
        let elapsed = clock.measure { groups = TimelineDayGroup.groups(events, now: now, calendar: calendar) }
        #expect(groups.reduce(0) { $0 + $1.events.count } == 20_000)
        #expect(groups.count == 90 || groups.count == 91)
        #expect(zip(groups, groups.dropFirst()).allSatisfy { $0.day > $1.day })
        // 6 ms in a debug build on mini-pro-1 (load average 430). 0.5 s is about 80 times that and leaves
        // room for a loaded host (#524) while still catching grouping that rescans the list per day or per event.
        #expect(elapsed < .milliseconds(500), "grouping took \(elapsed)")
    }
}
