import SwiftUI
import NetMonitorCore

// MARK: - macOS Timeline ViewModel

@MainActor
@Observable
final class TimelineMacViewModel {
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

    /// Kept, not computed, so a 20,000-event log groups once per change rather than per render.
    private(set) var groupedEvents: [TimelineDayGroup] = []

    private let service: any NetworkEventServiceProtocol
    private let calendar: Calendar
    private let now: () -> Date

    /// - Parameters:
    ///   - calendar: days, "Today" and date labels follow its time zone.
    ///   - now: the clock the ranges are measured from.
    init(
        service: any NetworkEventServiceProtocol = NetworkEventService.shared,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.calendar = calendar
        self.now = now
    }

    var filteredEvents: [NetworkEvent] {
        guard let filter = selectedFilter else { return events }
        return events.filter { $0.type == filter }
    }

    var hasEvents: Bool { !groupedEvents.isEmpty }

    func load() {
        events = selectedRange.bounds(now: now(), calendar: calendar)
            .map { service.events(from: $0.start, to: $0.end) } ?? service.events
    }

    // periphery:ignore
    func refresh() { load() }

    func clearAll() {
        service.clearAll()
        events = []
    }

    private func regroup() {
        groupedEvents = TimelineDayGroup.groups(filteredEvents, now: now(), calendar: calendar)
    }
}

// MARK: - TimelineView (macOS)

struct TimelineView: View {
    @State private var viewModel = TimelineMacViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if viewModel.hasEvents {
                // List is lazy, so a 20,000-event log stays smooth (#491 D3).
                List {
                    ForEach(viewModel.groupedEvents, id: \.day) { group in
                        Section(group.label) {
                            ForEach(group.events) { event in
                                MacTimelineRow(event: event)
                                    .accessibilityIdentifier("timeline_event_\(event.id.uuidString)")
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("timeline_list_events")
            } else {
                ContentUnavailableView(
                    "No Events",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(viewModel.selectedRange == .all && viewModel.selectedFilter == nil
                        ? "Network events will appear here as they occur."
                        : "No events match this range and filter.")
                )
                .accessibilityIdentifier("timeline_label_empty")
            }
        }
        // Keeps the children's identifiers on macOS 27.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen_networkTimeline")
        .task { viewModel.load() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("Network Timeline")
                .font(.headline)
            Spacer()
            Picker("Range", selection: $viewModel.selectedRange) {
                ForEach(TimelineRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("timeline_picker_range")
            Picker("Event Type", selection: $viewModel.selectedFilter) {
                Text("All Events").tag(NetworkEventType?.none)
                ForEach(NetworkEventType.allCases, id: \.rawValue) { type in
                    Text(type.displayName).tag(Optional(type))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 180)
            .accessibilityIdentifier("timeline_picker_eventType")

            Button("Clear All") { viewModel.clearAll() }
                .buttonStyle(.plain)
                .foregroundStyle(MacTheme.Colors.error)
                .font(.caption)
                .accessibilityIdentifier("timeline_button_clearAll")
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.smallCornerRadius, padding: MacTheme.Layout.cardPadding, showBorder: false)
    }
}

// MARK: - Event Row

private struct MacTimelineRow: View {
    let event: NetworkEvent

    private var severityColor: Color {
        MacTheme.Colors.severityColor(event.severity)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.type.iconName)
                .foregroundStyle(severityColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.body)
// swiftlint:disable:next identifier_name
                if let d = event.details {
                    Text(d).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(event.timestamp, style: .time)
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    TimelineView().frame(width: 500, height: 400)
}
