import SwiftUI
import NetMonitorCore

struct TimelineView: View {
    @State private var viewModel = TimelineViewModel()
    @State private var showingFilterSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.hasEvents {
                    eventList
                } else {
                    emptyState
                }
            }
            .themedBackground()
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilterSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            if viewModel.selectedFilter != nil {
                                Circle()
                                    .fill(Theme.Colors.accent)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .accessibilityIdentifier("timeline_button_filters")
                }

                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.events.isEmpty {
                        Button("Clear") {
                            viewModel.clearAll()
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.error)
                    }
                }
            }
            .refreshable {
                viewModel.refresh()
            }
            .task {
                viewModel.load()
            }
            .sheet(isPresented: $showingFilterSheet) {
                TimelineFilterSheet(viewModel: viewModel)
            }
            .accessibilityIdentifier("screen_networkTimeline")
        }
        .sheet(isPresented: $showingFilterSheet) {
            TimelineFilterSheet(viewModel: viewModel)
        }
    }

    private var eventList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(viewModel.groupedEvents, id: \.label) { group in
                    Section {
                        VStack(spacing: 1) {
                            ForEach(group.events) { event in
                                TimelineEventRow(event: event)
                            }
                        }
                        .glassCard()
                        .padding(.horizontal, Theme.Layout.screenPadding)
                        .padding(.bottom, Theme.Layout.itemSpacing)
                    } header: {
                        Text(group.label)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.Layout.screenPadding)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                    }
                }
            }
            .padding(.top, Theme.Layout.smallCornerRadius)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .accessibilityIdentifier("timeline_list")
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Layout.itemSpacing) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("No Events")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Network events will appear here as they occur.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("timeline_empty_state")
    }
}

// MARK: - Event Row

private struct TimelineEventRow: View {
    let event: NetworkEvent

    private var severityColor: Color {
        switch event.severity {
        case .success: return Theme.Colors.success
        case .warning: return Theme.Colors.warning
        case .error:   return Theme.Colors.error
        case .info:    return Theme.Colors.info
        }
    }

    var body: some View {
        HStack(spacing: Theme.Layout.itemSpacing) {
            // Severity indicator + icon
            ZStack {
                Circle()
                    .fill(severityColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: event.type.iconName)
                    .font(.caption)
                    .foregroundStyle(severityColor)
            }

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)

                if let details = event.details {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(event.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Theme.Layout.itemSpacing)
    }
}

// MARK: - Filter Sheet

struct TimelineFilterSheet: View {
    @Bindable var viewModel: TimelineViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        viewModel.showAll()
                        dismiss()
                    } label: {
                        HStack {
                            Label("All Events", systemImage: "list.bullet")
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            if viewModel.selectedFilter == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                    }
                    .accessibilityIdentifier("timeline_filter_show_all")
                }
                .listRowBackground(Theme.Colors.glassBackground)

                Section("Event Types") {
                    ForEach(NetworkEventType.allCases, id: \.rawValue) { type in
                        Button {
                            viewModel.applyFilter(type)
                            dismiss()
                        } label: {
                            HStack {
                                Label(type.displayName, systemImage: type.iconName)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Spacer()
                                if viewModel.selectedFilter == type {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.Colors.accent)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Theme.Colors.glassBackground)
            }
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle("Filter Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityIdentifier("timeline_filter_button_done")
                }
            }
        }
        .accessibilityIdentifier("screen_timeline_filter")
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    TimelineView()
}
