import Foundation
import NetMonitorCore

/// ViewModel for the Network Timeline view.
@MainActor
@Observable
final class TimelineViewModel {

    // MARK: - State

    /// The events in `selectedRange`, before the type filter.
    private(set) var events: [NetworkEvent] = [] {
        didSet { regroup() }
    }

    var selectedFilter: NetworkEventType? = nil {
        didSet { regroup() }
    }

    /// Reloads the log through `events(from:to:)` when changed (#491 D6).
    var selectedRange: TimelineRange = .all {
        didSet { load() }
    }

    /// Day sections, newest first. Kept, not computed, so a 20,000-event log groups once per
    /// change rather than once per section header.
    private(set) var groupedEvents: [TimelineDayGroup] = []

    /// Whether the log has any events at all, in or out of the range: Clear All deletes them all.
    private(set) var hasLoggedEvents = false
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
    private let calendar: Calendar
    private let now: () -> Date

    /// - Parameters:
    ///   - isScanning: whether a device scan is running; inference never runs during one.
    ///   - calendar: days, "Today" and date labels follow its time zone.
    ///   - now: the clock the ranges are measured from.
    init(
        service: any NetworkEventServiceProtocol = NetworkEventService.shared,
        insightService: any InsightServiceProtocol = UITestBootstrap.insightService ?? PhoneInsight.shared,
        isScanning: @escaping @MainActor () -> Bool = { DeviceDiscoveryService.shared.isScanning },
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.insightService = insightService
        self.isScanning = isScanning
        self.calendar = calendar
        self.now = now
    }

    /// The app's Timeline: the environment's event log, and its discovery service for the
    /// scanning state, so the UI-test fake's scans count too.
    convenience init(
        env: AppEnvironment,
        insightService: any InsightServiceProtocol = UITestBootstrap.insightService ?? PhoneInsight.shared
    ) {
        let discovery = env.deviceDiscovery
        self.init(service: env.eventService, insightService: insightService, isScanning: { discovery.isScanning })
    }

    // MARK: - Computed

    var filteredEvents: [NetworkEvent] {
        guard let filter = selectedFilter else { return events }
        return events.filter { $0.type == filter }
    }

    var hasEvents: Bool { !groupedEvents.isEmpty }

    // periphery:ignore
    var availableFilters: [NetworkEventType] {
        NetworkEventType.allCases
    }

    var selectedFilterName: String {
        selectedFilter?.displayName ?? "All Events"
    }

    // MARK: - Actions

    func load() {
        // `events(from:to:)` includes its end; tomorrow's first instant isn't today.
        events = selectedRange.bounds(now: now(), calendar: calendar)
            .map { bounds in service.events(from: bounds.start, to: bounds.end).filter { $0.timestamp < bounds.end } }
            ?? service.events
        hasLoggedEvents = !service.events.isEmpty
    }

    func refresh() {
        load()
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
        hasLoggedEvents = false
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
        let start = group.day
        let end = calendar.dateInterval(of: .day, for: start)?.end.addingTimeInterval(-0.001) ?? group.newest.timestamp
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
        switch await InsightSummarizer.outcome(for: request, service: insightService, timeout: ChangeBriefViewModel.timeout) {
        case let .answer(answer):
            summaries[key] = .finished(ChangeSummary(keyPoints: request.observations, text: answer.text, source: answer.source))
        case .refused:
            summaries[key] = .unavailable
        case .tryLater:
            // A Mac that was busy or went away (#457): forget the day, so Summarize asks again.
            summaries[key] = nil
        }
    }

    /// The shown day section labelled `label`, its start and its newest event.
    private func dayGroup(_ label: String) -> (label: String, day: Date, newest: NetworkEvent)? {
        guard let group = groupedEvents.first(where: { $0.label == label }),
              let newest = group.events.first
        else { return nil }
        return (label, group.day, newest)
    }

    /// The day, the filter and the day's newest event: a summary is shown only for what it summarized.
    private func summaryKey(for group: (label: String, day: Date, newest: NetworkEvent)) -> String {
        "\(group.label)|\(selectedFilter?.rawValue ?? "all")|\(group.newest.id)"
    }

    // MARK: - Date Grouping

    private func regroup() {
        groupedEvents = TimelineDayGroup.groups(filteredEvents, now: now(), calendar: calendar)
    }
}
