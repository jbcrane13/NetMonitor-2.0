import Foundation
import Testing
@testable import NetMonitorCore

@Suite("TimelineRange (#491 S3)")
struct TimelineRangeTests {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    /// A moment written as local wall-clock time in `calendar`'s zone.
    private func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        // swiftlint:disable:next force_unwrapping
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test("All has no bounds")
    func allIsUnbounded() {
        let cal = calendar("America/New_York")
        #expect(TimelineRange.all.bounds(now: date(cal, 2026, 6, 1, 12), calendar: cal) == nil)
    }

    @Test("Today runs from local midnight to the next midnight")
    func todayIsTheCalendarDay() throws {
        let cal = calendar("America/New_York")
        let bounds = try #require(TimelineRange.today.bounds(now: date(cal, 2026, 6, 1, 15, 30), calendar: cal))
        #expect(bounds.start == date(cal, 2026, 6, 1))
        #expect(bounds.end == date(cal, 2026, 6, 2))
    }

    @Test("Today on a spring-forward day is 23 hours long")
    func todayOnSpringForward() throws {
        let cal = calendar("America/New_York")
        // 2026-03-08: clocks jump from 02:00 to 03:00 in New York.
        let bounds = try #require(TimelineRange.today.bounds(now: date(cal, 2026, 3, 8, 22), calendar: cal))
        #expect(bounds.start == Date(timeIntervalSince1970: 1_772_946_000)) // 2026-03-08 05:00 UTC
        #expect(bounds.end.timeIntervalSince(bounds.start) == 23 * 3600)
    }

    @Test("Today on a fall-back day is 25 hours long")
    func todayOnFallBack() throws {
        let cal = calendar("America/New_York")
        // 2026-11-01: clocks fall back from 02:00 to 01:00.
        let bounds = try #require(TimelineRange.today.bounds(now: date(cal, 2026, 11, 1, 23, 59), calendar: cal))
        #expect(bounds.start == Date(timeIntervalSince1970: 1_793_505_600)) // 2026-11-01 04:00 UTC
        #expect(bounds.end.timeIntervalSince(bounds.start) == 25 * 3600)
    }

    @Test("Today starts at 01:00 where DST skips midnight")
    func todayWhereMidnightIsSkipped() throws {
        let cal = calendar("America/Santiago")
        // 2026-09-06: Chile's clocks jump from 00:00 to 01:00, so the day has no midnight.
        let bounds = try #require(TimelineRange.today.bounds(now: date(cal, 2026, 9, 6, 12), calendar: cal))
        #expect(cal.component(.hour, from: bounds.start) == 1)
        #expect(cal.component(.day, from: bounds.start) == 6)
        #expect(bounds.start == Date(timeIntervalSince1970: 1_788_667_200)) // 2026-09-06 04:00 UTC
    }

    @Test("7 days covers today and the six days before, across a month boundary")
    func sevenDaysAcrossMonth() throws {
        let cal = calendar("Europe/London")
        let bounds = try #require(TimelineRange.sevenDays.bounds(now: date(cal, 2026, 3, 3, 9), calendar: cal))
        #expect(bounds.start == date(cal, 2026, 2, 25))
        #expect(bounds.end == date(cal, 2026, 3, 4))
    }

    @Test("7 days across a year boundary")
    func sevenDaysAcrossYear() throws {
        let cal = calendar("Asia/Tokyo")
        let bounds = try #require(TimelineRange.sevenDays.bounds(now: date(cal, 2027, 1, 2, 8), calendar: cal))
        #expect(bounds.start == date(cal, 2026, 12, 27))
        #expect(bounds.end == date(cal, 2027, 1, 3))
    }

    @Test("30 days across a DST change starts at local midnight")
    func thirtyDaysAcrossDST() throws {
        let cal = calendar("Europe/London")
        // 2026-03-29: London moves to BST. 30 days back from 2026-04-10 is 2026-03-12, in GMT.
        let bounds = try #require(TimelineRange.thirtyDays.bounds(now: date(cal, 2026, 4, 10, 18), calendar: cal))
        #expect(bounds.start == Date(timeIntervalSince1970: 1_773_273_600)) // 2026-03-12 00:00 UTC
        #expect(bounds.end == date(cal, 2026, 4, 11))
    }

    @Test("Titles in picker order")
    func titles() {
        #expect(TimelineRange.allCases.map(\.title) == ["Today", "7 Days", "30 Days", "All"])
    }
}
