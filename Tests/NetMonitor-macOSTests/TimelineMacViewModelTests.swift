import Foundation
import Testing
@testable import NetMonitor_macOS
import NetMonitorCore

/// An event log over a plain array, so a 20,000-event set loads without 20,000 `log` calls.
private final class MockArrayEventService: NetworkEventServiceProtocol, @unchecked Sendable {
    var stored: [NetworkEvent]
    private(set) var rangeQueries: [(Date, Date)] = []
    init(_ events: [NetworkEvent] = []) { stored = events }

    var events: [NetworkEvent] { stored }
    func log(_ event: NetworkEvent) { stored.insert(event, at: 0) }
    func events(ofType type: NetworkEventType) -> [NetworkEvent] { stored.filter { $0.type == type } }
    func events(from start: Date, to end: Date) -> [NetworkEvent] {
        rangeQueries.append((start, end))
        return stored.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    func removeEvents(olderThan cutoff: Date) { stored.removeAll { $0.timestamp < cutoff } }
    func clearAll() { stored.removeAll() }
}

@Suite("TimelineMacViewModel (#491 S3)")
@MainActor
struct TimelineMacViewModelTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private func date(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        // swiftlint:disable:next force_unwrapping
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private var now: Date { date(11, 23, 10) }

    private func makeVM(_ service: MockArrayEventService) -> TimelineMacViewModel {
        let now = now
        return TimelineMacViewModel(service: service, calendar: calendar, now: { now })
    }

    private func seeded() -> MockArrayEventService {
        MockArrayEventService([
            NetworkEvent(type: .deviceJoined, timestamp: date(11, 23, 9), title: "Joined today"),
            NetworkEvent(type: .scanComplete, timestamp: date(11, 23, 8), title: "Scan today"),
            NetworkEvent(type: .deviceJoined, timestamp: date(11, 20), title: "Joined 3 days ago"),
            NetworkEvent(type: .deviceLeft, timestamp: date(11, 13), title: "Left 10 days ago"),
            NetworkEvent(type: .deviceJoined, timestamp: date(10, 1), title: "Joined in October")
        ])
    }

    private func titles(_ vm: TimelineMacViewModel) -> [String] {
        vm.groupedEvents.flatMap { $0.events.map(\.title) }
    }

    @Test("All is the default and shows every event")
    func defaultIsAll() {
        let vm = makeVM(seeded())
        vm.load()
        #expect(vm.selectedRange == .all)
        #expect(titles(vm).count == 5)
    }

    @Test("Today shows only today's events, read through events(from:to:)")
    func todayRange() {
        let service = seeded()
        let vm = makeVM(service)
        vm.selectedRange = .today
        #expect(titles(vm) == ["Joined today", "Scan today"])
        #expect(service.rangeQueries.last?.0 == date(11, 23, 0))
        #expect(service.rangeQueries.last?.1 == date(11, 24, 0))
    }

    @Test("7 and 30 days cut off at the right calendar day")
    func sevenAndThirtyDays() {
        let vm = makeVM(seeded())
        vm.selectedRange = .sevenDays
        #expect(titles(vm) == ["Joined today", "Scan today", "Joined 3 days ago"])
        vm.selectedRange = .thirtyDays
        #expect(titles(vm) == ["Joined today", "Scan today", "Joined 3 days ago", "Left 10 days ago"])
        vm.selectedRange = .all
        #expect(titles(vm).count == 5)
    }

    @Test("The type filter applies inside the range")
    func filterWithinRange() {
        let vm = makeVM(seeded())
        vm.selectedRange = .sevenDays
        vm.selectedFilter = .deviceJoined
        #expect(titles(vm) == ["Joined today", "Joined 3 days ago"])
        vm.selectedRange = .all
        #expect(titles(vm) == ["Joined today", "Joined 3 days ago", "Joined in October"])
        vm.selectedFilter = .scanComplete
        vm.selectedRange = .today
        #expect(titles(vm) == ["Scan today"])
        vm.selectedFilter = .deviceLeft
        #expect(!vm.hasEvents)
    }

    @Test("Day groups are newest first by date")
    func chronologicalGroups() {
        let vm = makeVM(seeded())
        vm.load()
        #expect(vm.groupedEvents.map(\.label) == ["Today", "Nov 20, 2026", "Nov 13, 2026", "Oct 1, 2026"])
    }

    @Test("Refresh picks up an event logged after the Timeline opened")
    func refreshSeesNewEvents() {
        let service = seeded()
        let vm = makeVM(service)
        vm.selectedRange = .today
        service.log(NetworkEvent(type: .deviceJoined, timestamp: date(11, 23, 9), title: "Joined later"))
        vm.refresh()
        #expect(titles(vm).contains("Joined later"))
    }

    @Test("An event at exactly tomorrow's midnight is not Today")
    func todayExcludesTomorrowsMidnight() {
        let service = seeded()
        service.log(NetworkEvent(type: .deviceJoined, timestamp: date(11, 24, 0), title: "Midnight"))
        let vm = makeVM(service)
        vm.selectedRange = .today
        #expect(!titles(vm).contains("Midnight"))
        vm.selectedRange = .all
        #expect(titles(vm).contains("Midnight"))
    }

    @Test("Clear All stays offered while the log has events outside the range")
    func logHasEventsOutsideTheRange() {
        let vm = makeVM(MockArrayEventService([
            NetworkEvent(type: .deviceLeft, timestamp: date(11, 13), title: "Left 10 days ago")
        ]))
        vm.selectedRange = .today
        #expect(!vm.hasEvents)
        #expect(vm.hasLoggedEvents)
        vm.clearAll()
        #expect(!vm.hasLoggedEvents)
    }

    @Test("Clear All empties the log and the list")
    func clearAll() {
        let service = seeded()
        let vm = makeVM(service)
        vm.load()
        vm.clearAll()
        #expect(service.stored.isEmpty)
        #expect(!vm.hasEvents)
        #expect(vm.groupedEvents.isEmpty)
    }

    @Test("20,000 events load and group within the bound")
    func twentyThousandEvents() {
        let now = now
        let service = MockArrayEventService((0 ..< 20_000).map { index in
            NetworkEvent(type: .deviceJoined, timestamp: now.addingTimeInterval(-Double(index) * 60), title: "e\(index)")
        })
        let vm = makeVM(service)
        let elapsed = ContinuousClock().measure { vm.load() }
        #expect(vm.groupedEvents.reduce(0) { $0 + $1.events.count } == 20_000)
        // Same bound and reasoning as the Core grouping test (TimelineDayGroupTests).
        #expect(elapsed < .milliseconds(500), "load took \(elapsed)")
    }
}

@Suite("Timeline tool (#491 D5)")
struct TimelineToolRegistrationTests {
    @Test("Timeline is a Monitoring tool whose card id is tools_card_timeline")
    func listedUnderMonitoring() {
        #expect(ToolCategory.allCases.filter { $0.tools.contains(.timeline) } == [.monitoring])
        #expect(NetworkTool.timeline.cardIdentifier == "tools_card_timeline")
        #expect(NetworkTool.portForwards.cardIdentifier == "tools_card_port_forwards")
    }
}
