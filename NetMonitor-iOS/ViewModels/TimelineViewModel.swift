import Foundation
import NetMonitorCore

/// ViewModel for the Network Timeline view.
@MainActor
@Observable
final class TimelineViewModel {

    // MARK: - State

    var events: [NetworkEvent] = []
    var selectedFilter: NetworkEventType? = nil
    var isShowingFilterSheet: Bool = false

    // MARK: - Dependencies

    private let service: any NetworkEventServiceProtocol

    init(service: any NetworkEventServiceProtocol = NetworkEventService.shared) {
        self.service = service
    }

    // MARK: - Computed

    var filteredEvents: [NetworkEvent] {
        guard let filter = selectedFilter else { return events }
        return events.filter { $0.type == filter }
    }

    var hasEvents: Bool { !filteredEvents.isEmpty }

    var availableFilters: [NetworkEventType] {
        NetworkEventType.allCases
    }

    var selectedFilterName: String {
        selectedFilter?.displayName ?? "All Events"
    }

    // MARK: - Actions

    func load() {
        events = service.events
    }

    func refresh() {
        events = service.events
    }

    func showAll() {
        selectedFilter = nil
        isShowingFilterSheet = false
    }

    func applyFilter(_ type: NetworkEventType?) {
        selectedFilter = type
        isShowingFilterSheet = false
    }

    func clearFilter() {
        selectedFilter = nil
    }

    func clearAll() {
        service.clearAll()
        events = []
    }

    // MARK: - Date Grouping

    /// Groups filtered events by relative date label (Today, Yesterday, date string).
    var groupedEvents: [(label: String, events: [NetworkEvent])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        var groups: [String: [NetworkEvent]] = [:]
        for event in filteredEvents {
            let day = calendar.startOfDay(for: event.timestamp)
            let label: String
            if day == today {
                label = "Today"
            } else if day == yesterday {
                label = "Yesterday"
            } else {
                label = DateFormatter.localizedString(from: day, dateStyle: .medium, timeStyle: .none)
            }
            groups[label, default: []].append(event)
        }

        // Sort groups: Today first, then Yesterday, then older dates descending
        let sortedKeys = groups.keys.sorted { a, b in
            if a == "Today" { return true }
            if b == "Today" { return false }
            if a == "Yesterday" { return true }
            if b == "Yesterday" { return false }
            return a > b
        }
        return sortedKeys.compactMap { key in
            guard let evts = groups[key] else { return nil }
            return (label: key, events: evts)
        }
    }
}
