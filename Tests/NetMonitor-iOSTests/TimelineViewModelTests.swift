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

    func log(type: NetworkEventType, title: String, details: String?, severity: NetworkEventSeverity) {
        log(NetworkEvent(type: type, title: title, details: details, severity: severity))
    }

    func events(ofType type: NetworkEventType) -> [NetworkEvent] {
        mockEvents.filter { $0.type == type }
    }

    func events(from start: Date, to end: Date) -> [NetworkEvent] {
        mockEvents.filter { $0.timestamp >= start && $0.timestamp <= end }
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
        let a = NetworkEvent(type: .toolRun, title: "A")
        let b = NetworkEvent(type: .toolRun, title: "B")
        #expect(a.id != b.id)
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
