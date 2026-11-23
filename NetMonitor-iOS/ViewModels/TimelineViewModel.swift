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

    /// A day's summary from the on-device model (#453).
    enum DaySummary: Equatable {
        case loading
        case finished(ChangeSummary)
        /// The model failed, or there was nothing to summarize. Shown as a short note.
        case unavailable
    }

    /// Summaries by `summaryKey`, so a change of filter or a new event drops them.
    private var summaries: [String: DaySummary] = [:]

    // MARK: - Dependencies

    private let service: any NetworkEventServiceProtocol
    private let insightService: any InsightServiceProtocol
    private let isScanning: @MainActor () -> Bool

    /// - Parameter isScanning: whether a device scan is running; inference never runs during one.
    init(
        service: any NetworkEventServiceProtocol = NetworkEventService.shared,
        insightService: any InsightServiceProtocol = UITestBootstrap.insightService ?? InsightService.shared,
        isScanning: @escaping @MainActor () -> Bool = { DeviceDiscoveryService.shared.isScanning }
    ) {
        self.service = service
        self.insightService = insightService
        self.isScanning = isScanning
    }

    // MARK: - Computed

    var filteredEvents: [NetworkEvent] {
        guard let filter = selectedFilter else { return events }
        return events.filter { $0.type == filter }
    }

    var hasEvents: Bool { !filteredEvents.isEmpty }

    // periphery:ignore
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

    // periphery:ignore
    func clearFilter() {
        selectedFilter = nil
    }

    func clearAll() {
        service.clearAll()
        events = []
    }

    // MARK: - Summaries

    /// Whether the day sections offer "Summarize": only where the on-device model is available,
    /// and not while the filter shows only scan completions or tool runs, which are routine
    /// and never summarized.
    var canSummarize: Bool {
        insightService.isAvailable && (selectedFilter.map(ChangeDigestBuilder.changeTypes.contains) ?? true)
    }

    /// The summary of the day section labelled `label` under the current filter, if asked for.
    func summary(for label: String) -> DaySummary? {
        dayGroup(label).flatMap { summaries[summaryKey(for: $0)] }
    }

    /// Summarizes the day section labelled `label`, with the current type filter.
    /// - Parameters:
    ///   - savedDevices: name devices through `LocalDevice.displayName`.
    ///   - speedTests: saved speed tests, newest first or in any order; the day's latest is
    ///     compared with the one before it.
    func summarize(_ label: String, savedDevices: [LocalDevice], speedTests: [SpeedTestResult]) async {
        guard let group = dayGroup(label) else { return }
        let key = summaryKey(for: group)
        let filter = selectedFilter
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: group.newest.timestamp)
        let end = calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-0.001) ?? group.newest.timestamp
        guard !isScanning(), let request = ChangeDigestBuilder.request(
            events: events, from: start, to: end, filter: filter,
            deviceNames: ChangeDigestBuilder.deviceNames(savedDevices),
            speedTests: speedTests,
            subject: ChangeDigestBuilder.daySubject(start, filter: filter, calendar: calendar)
        ) else {
            summaries[key] = .unavailable
            return
        }
        summaries[key] = .loading
        let text = await InsightSummarizer.summary(for: request, service: insightService, timeout: ChangeBriefViewModel.timeout)
        summaries[key] = text.map { .finished(ChangeSummary(keyPoints: request.observations, text: $0)) } ?? .unavailable
    }

    /// The shown day section labelled `label` and its newest event.
    private func dayGroup(_ label: String) -> (label: String, newest: NetworkEvent)? {
        guard let group = groupedEvents.first(where: { $0.label == label }),
              let newest = group.events.max(by: { $0.timestamp < $1.timestamp })
        else { return nil }
        return (label, newest)
    }

    /// The day, the filter and the day's newest event: a summary is shown only for what it summarized.
    private func summaryKey(for group: (label: String, newest: NetworkEvent)) -> String {
        "\(group.label)|\(selectedFilter?.rawValue ?? "all")|\(group.newest.id)"
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
            if a == "Today" {
                return true
            }
            if b == "Today" {
                return false
            }
            if a == "Yesterday" {
                return true
            }
            if b == "Yesterday" {
                return false
            }
            return a > b
        }
        return sortedKeys.compactMap { key in
            guard let evts = groups[key] else { return nil }
            return (label: key, events: evts)
        }
    }
}
