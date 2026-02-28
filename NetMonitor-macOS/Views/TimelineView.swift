import SwiftUI
import NetMonitorCore

// MARK: - macOS Timeline ViewModel

@MainActor
@Observable
final class TimelineMacViewModel {
    var events: [NetworkEvent] = []
    var selectedFilter: NetworkEventType? = nil

    private let service: any NetworkEventServiceProtocol

    init(service: any NetworkEventServiceProtocol = NetworkEventService.shared) {
        self.service = service
    }

    var filteredEvents: [NetworkEvent] {
        guard let f = selectedFilter else { return events }
        return events.filter { $0.type == f }
    }

    var hasEvents: Bool { !filteredEvents.isEmpty }

    var groupedEvents: [(label: String, events: [NetworkEvent])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        var groups: [String: [NetworkEvent]] = [:]
        for e in filteredEvents {
            let day = cal.startOfDay(for: e.timestamp)
            let label: String
            if day == today { label = "Today" }
            else if day == yesterday { label = "Yesterday" }
            else { label = DateFormatter.localizedString(from: day, dateStyle: .medium, timeStyle: .none) }
            groups[label, default: []].append(e)
        }
        let keys = groups.keys.sorted {
            if $0 == "Today" { return true }
            if $1 == "Today" { return false }
            if $0 == "Yesterday" { return true }
            if $1 == "Yesterday" { return false }
            return $0 > $1
        }
        return keys.compactMap { k in groups[k].map { (label: k, events: $0) } }
    }

    func load() { events = service.events }
    func refresh() { events = service.events }
    func clearAll() { service.clearAll()
    events = []
    }

    func applyFilter(_ type: NetworkEventType?) { selectedFilter = type }
}

// MARK: - TimelineView (macOS)

struct TimelineView: View {
    @State private var viewModel = TimelineMacViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Text("Network Timeline")
                    .font(.headline)
                Spacer()
                Picker("Filter", selection: Binding(
                    get: { viewModel.selectedFilter },
                    set: { viewModel.applyFilter($0) }
                )) {
                    Text("All Events").tag(NetworkEventType?.none)
                    ForEach(NetworkEventType.allCases, id: \.rawValue) { type in
                        Text(type.displayName).tag(Optional(type))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)

                Button("Clear All") { viewModel.clearAll() }
                    .buttonStyle(.plain)
                    .foregroundStyle(MacTheme.Colors.error)
                    .font(.caption)
            }
            .macGlassCard(cornerRadius: MacTheme.Layout.smallCornerRadius, padding: MacTheme.Layout.cardPadding, showBorder: false)

            Divider()

            if viewModel.hasEvents {
                List {
                    ForEach(viewModel.groupedEvents, id: \.label) { group in
                        Section(group.label) {
                            ForEach(group.events) { event in
                                MacTimelineRow(event: event)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            } else {
                ContentUnavailableView(
                    "No Events",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Network events will appear here as they occur.")
                )
            }
        }
        .accessibilityIdentifier("screen_networkTimeline")
        .task { viewModel.load() }
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
