import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

// MARK: - Mock Event Service

private final class MockNetworkEventService: NetworkEventServiceProtocol, @unchecked Sendable {
    var mockEvents: [NetworkEvent] = []
    var clearCallCount = 0

    var events: [NetworkEvent] { mockEvents }

    func log(_ event: NetworkEvent) { mockEvents.insert(event, at: 0) }

    func events(ofType type: NetworkEventType) -> [NetworkEvent] {
        mockEvents.filter { $0.type == type }
    }

    func events(from start: Date, to end: Date) -> [NetworkEvent] {
        mockEvents.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    func removeEvents(olderThan cutoff: Date) {
        mockEvents.removeAll { $0.timestamp < cutoff }
    }

    func clearAll() {
        clearCallCount += 1
        mockEvents.removeAll()
    }
}

// MARK: - Tests

@MainActor
struct TimelineViewModelTests {

    @Test func initialStateIsEmpty() {
        let vm = TimelineViewModel(service: MockNetworkEventService())
        #expect(vm.events.isEmpty)
        #expect(vm.selectedFilter == nil)
        #expect(vm.hasEvents == false)
    }

    @Test func loadFetchesEvents() {
        let mock = MockNetworkEventService()
        mock.mockEvents = [
            NetworkEvent(type: .scanComplete, title: "Scan done"),
            NetworkEvent(type: .deviceJoined, title: "Device joined")
        ]
        let vm = TimelineViewModel(service: mock)
        vm.load()
        #expect(vm.events.count == 2)
        #expect(vm.hasEvents == true)
    }

    @Test func filteredEventsReturnsAllWhenNoFilter() {
        let mock = MockNetworkEventService()
        mock.mockEvents = [
            NetworkEvent(type: .scanComplete, title: "Scan"),
            NetworkEvent(type: .deviceJoined, title: "Joined")
        ]
        let vm = TimelineViewModel(service: mock)
        vm.load()
        #expect(vm.filteredEvents.count == 2)
    }

    @Test func filteredEventsReturnsOnlyMatchingType() {
        let mock = MockNetworkEventService()
        mock.mockEvents = [
            NetworkEvent(type: .scanComplete, title: "Scan"),
            NetworkEvent(type: .deviceJoined, title: "Joined"),
            NetworkEvent(type: .deviceJoined, title: "Another device")
        ]
        let vm = TimelineViewModel(service: mock)
        vm.load()
        vm.selectedFilter = .deviceJoined
        #expect(vm.filteredEvents.count == 2)
    }

    @Test func showAllClearsFilterAndDismissesSheet() {
        let vm = TimelineViewModel(service: MockNetworkEventService())
        vm.selectedFilter = .scanComplete
        vm.isShowingFilterSheet = true
        vm.showAll()
        #expect(vm.selectedFilter == nil)
        #expect(vm.isShowingFilterSheet == false)
    }

    @Test func applyFilterSetsFilterAndDismissesSheet() {
        let vm = TimelineViewModel(service: MockNetworkEventService())
        vm.isShowingFilterSheet = true
        vm.applyFilter(.vpnConnected)
        #expect(vm.selectedFilter == .vpnConnected)
        #expect(vm.isShowingFilterSheet == false)
    }

    @Test func clearAllDelegatesToService() {
        let mock = MockNetworkEventService()
        mock.mockEvents = [NetworkEvent(type: .toolRun, title: "Test")]
        let vm = TimelineViewModel(service: mock)
        vm.load()
        vm.clearAll()
        #expect(vm.events.isEmpty)
        #expect(mock.clearCallCount == 1)
    }

    @Test func selectedFilterNameShowsAllEventsWhenNil() {
        let vm = TimelineViewModel(service: MockNetworkEventService())
        #expect(vm.selectedFilterName == "All Events")
    }

    @Test func selectedFilterNameShowsTypeDisplayNameWhenFiltered() {
        let vm = TimelineViewModel(service: MockNetworkEventService())
        vm.selectedFilter = .deviceJoined
        #expect(vm.selectedFilterName == NetworkEventType.deviceJoined.displayName)
    }

    @Test func refreshReloadsEvents() {
        let mock = MockNetworkEventService()
        let vm = TimelineViewModel(service: mock)
        vm.load()
        #expect(vm.events.isEmpty)

        mock.mockEvents = [NetworkEvent(type: .connectivityChange, title: "Network changed")]
        vm.refresh()
        #expect(vm.events.count == 1)
    }

    @Test func groupedEventsGroupsToday() {
        let mock = MockNetworkEventService()
        mock.mockEvents = [
            NetworkEvent(type: .toolRun, timestamp: Date(), title: "Run 1"),
            NetworkEvent(type: .toolRun, timestamp: Date(), title: "Run 2")
        ]
        let vm = TimelineViewModel(service: mock)
        vm.load()
        let groups = vm.groupedEvents
        #expect(groups.first?.label == "Today")
        #expect(groups.first?.events.count == 2)
    }
}

// MARK: - Ranges and day order (#491 S3)

@Suite("TimelineViewModel ranges")
@MainActor
struct TimelineViewModelRangeTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private func date(_ month: Int, _ day: Int, _ hour: Int = 12, year: Int = 2027) -> Date {
        // swiftlint:disable:next force_unwrapping
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// 2027-01-03 10:00 in Berlin, so the ranges cross the year boundary.
    private func makeVM() -> (TimelineViewModel, MockNetworkEventService) {
        let mock = MockNetworkEventService()
        mock.mockEvents = [
            NetworkEvent(type: .deviceJoined, timestamp: date(1, 3, 9), title: "Joined today"),
            NetworkEvent(type: .deviceLeft, timestamp: date(1, 3, 1), title: "Left today"),
            NetworkEvent(type: .deviceJoined, timestamp: date(1, 2, 23), title: "Joined yesterday"),
            NetworkEvent(type: .deviceJoined, timestamp: date(12, 28, 0, year: 2026), title: "Joined at the start of 7 days"),
            NetworkEvent(type: .deviceLeft, timestamp: date(1, 3, 0).addingTimeInterval(-6 * 86400 - 1), title: "Left just before 7 days"),
            NetworkEvent(type: .deviceJoined, timestamp: date(11, 5, year: 2026), title: "Joined in November")
        ]
        let now = date(1, 3, 10)
        return (TimelineViewModel(service: mock, calendar: calendar, now: { now }), mock)
    }

    private func titles(_ vm: TimelineViewModel) -> [String] {
        vm.groupedEvents.flatMap { $0.events.map(\.title) }
    }

    @Test func allIsTheDefault() {
        let (vm, _) = makeVM()
        vm.load()
        #expect(vm.selectedRange == .all)
        #expect(titles(vm).count == 6)
    }

    @Test func todayStartsAtLocalMidnight() {
        let (vm, _) = makeVM()
        vm.selectedRange = .today
        #expect(titles(vm) == ["Joined today", "Left today"])
    }

    @Test func sevenDaysStartsAtMidnightSixDaysAgoAcrossTheYear() {
        let (vm, _) = makeVM()
        vm.selectedRange = .sevenDays
        #expect(titles(vm) == ["Joined today", "Left today", "Joined yesterday", "Joined at the start of 7 days"])
        #expect(vm.groupedEvents.last?.label == "Dec 28, 2026")
    }

    @Test func theTypeFilterAppliesInsideTheRange() {
        let (vm, _) = makeVM()
        vm.selectedRange = .thirtyDays
        vm.applyFilter(.deviceLeft)
        #expect(titles(vm) == ["Left today", "Left just before 7 days"])
        vm.selectedRange = .today
        #expect(titles(vm) == ["Left today"])
        vm.applyFilter(.scanComplete)
        #expect(!vm.hasEvents)
    }

    @Test func olderDaysAreInDateOrderNotLabelOrder() {
        let (vm, _) = makeVM()
        vm.load()
        // Alphabetically "Nov 5, 2026" sorts before "Dec 27, 2026"; by date it is last.
        #expect(vm.groupedEvents.map(\.label) == ["Today", "Yesterday", "Dec 28, 2026", "Dec 27, 2026", "Nov 5, 2026"])
    }

    @Test func aNewEventShowsOnRefreshWithinTheRange() {
        let (vm, mock) = makeVM()
        vm.selectedRange = .today
        mock.log(NetworkEvent(type: .scanComplete, timestamp: date(1, 3, 9), title: "Scan Complete"))
        vm.refresh()
        #expect(titles(vm).contains("Scan Complete"))
    }
}

// MARK: - NetworkEvent Model Tests

struct NetworkEventTests {

    @Test func defaultInitUsesCurrentDate() {
        let before = Date()
        let event = NetworkEvent(type: .toolRun, title: "Test")
        let after = Date()
        #expect(event.timestamp >= before)
        #expect(event.timestamp <= after)
    }

    @Test func idIsUniquePerInstance() {
        let first = NetworkEvent(type: .toolRun, title: "A")
        let second = NetworkEvent(type: .toolRun, title: "B")
        #expect(first.id != second.id)
    }

    @Test func typeDisplayNamesAreNonEmpty() {
        for type in NetworkEventType.allCases {
            #expect(!type.displayName.isEmpty)
            #expect(!type.iconName.isEmpty)
        }
    }

    @Test func severityDefaultsToInfo() {
        let event = NetworkEvent(type: .deviceJoined, title: "Test")
        #expect(event.severity == .info)
    }
}
