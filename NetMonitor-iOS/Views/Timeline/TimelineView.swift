import SwiftUI
import NetMonitorCore
import SwiftData

struct TimelineView: View {
    @State private var viewModel: TimelineViewModel
    @State private var showingFilterSheet = false
    @State private var isConfirmingClear = false
    /// Set once the list has scrolled to `focusDay`, so later changes don't scroll it back.
    @State private var hasFocused = false
    /// Summaries name devices through their saved rows and compare speed tests (#453).
    @Query(Self.savedDevicesDescriptor) private var savedDevices: [LocalDevice]
    @Query(Self.speedTestsDescriptor) private var speedTests: [SpeedTestResult]

    private static var savedDevicesDescriptor: FetchDescriptor<LocalDevice> {
        var descriptor = FetchDescriptor<LocalDevice>()
        descriptor.fetchLimit = 500
        return descriptor
    }

    private static var speedTestsDescriptor: FetchDescriptor<SpeedTestResult> {
        var descriptor = FetchDescriptor<SpeedTestResult>(sortBy: [SortDescriptor(\SpeedTestResult.timestamp, order: .reverse)])
        descriptor.fetchLimit = 500
        return descriptor
    }

    /// The day to scroll to when the list loads: an Ask citation's event (#452).
    private let focusDay: Date?

    init(env: AppEnvironment, focusDay: Date? = nil) {
        _viewModel = State(initialValue: TimelineViewModel(env: env))
        self.focusDay = focusDay
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                rangePicker
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
                    // Whenever the log has events, even outside the range: it deletes them all.
                    if viewModel.hasLoggedEvents {
                        Button("Clear All") {
                            isConfirmingClear = true
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.error)
                        .accessibilityIdentifier("timeline_button_clearAll")
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
            .confirmationDialog("Delete all network events?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
                Button("Clear All", role: .destructive) {
                    viewModel.clearAll()
                }
                .accessibilityIdentifier("timeline_button_confirmClearAll")
            } message: {
                Text("This removes every event in the log, not just the ones shown.")
            }
            // Keeps the empty state's and the list's own identifiers on iOS 26+.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen_networkTimeline")
        }
        .sheet(isPresented: $showingFilterSheet) {
            TimelineFilterSheet(viewModel: viewModel)
        }
    }

    private var eventList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                eventSections
            }
            .task(id: viewModel.groupedEvents.count) {
                // The range is All on open, so the focused day's section is in the list.
                guard !hasFocused, let focusDay, !viewModel.groupedEvents.isEmpty else { return }
                proxy.scrollTo(viewModel.day(of: focusDay), anchor: .top)
                hasFocused = true
            }
        }
        .accessibilityIdentifier("timeline_list_events")
    }

    private var eventSections: some View {
        LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
            ForEach(viewModel.groupedEvents, id: \.day) { group in
                Section {
                    if let summary = viewModel.summary(for: group.label) {
                        TimelineDaySummary(summary: summary, label: group.label)
                            .padding(.horizontal, Theme.Layout.screenPadding)
                            .padding(.bottom, Theme.Layout.itemSpacing)
                    }
                    // Lazy too, so a day of thousands of events stays smooth (#491 D3).
                    LazyVStack(spacing: 1) {
                        ForEach(group.events) { event in
                            TimelineEventRow(event: event)
                        }
                    }
                    .glassCard()
                    .padding(.horizontal, Theme.Layout.screenPadding)
                    .padding(.bottom, Theme.Layout.itemSpacing)
                } header: {
                    sectionHeader(group.label)
                }
                .id(group.day)
            }
        }
        .padding(.top, Theme.Layout.smallCornerRadius)
        .padding(.bottom, Theme.Layout.sectionSpacing)
    }

    private var rangePicker: some View {
        Picker("Range", selection: $viewModel.selectedRange) {
            ForEach(TimelineRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.Layout.screenPadding)
        .padding(.vertical, Theme.Layout.smallCornerRadius)
        .accessibilityIdentifier("timeline_picker_range")
    }

    private func sectionHeader(_ label: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            // Hidden where the on-device model is unavailable, and while a summary is on its way.
            if viewModel.canSummarize, viewModel.summary(for: label) != .loading {
                Button {
                    Task { await viewModel.summarize(label, savedDevices: savedDevices, speedTests: speedTests) }
                } label: {
                    Label("Summarize", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                }
                .accessibilityIdentifier("timeline_button_summarize_\(label)")
            }
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
        .padding(.vertical, 6)
        .liquidGlassBackground()
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
                // On the text: iOS 26+ gives the stack no element of its own to carry it.
                .accessibilityIdentifier("timeline_label_emptyState")
            Text(viewModel.hasLoggedEvents
                ? "No events match this range and filter."
                : "Network events will appear here as they occur.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Day Summary (#453)

private struct TimelineDaySummary: View {
    let summary: TimelineViewModel.DaySummary
    let label: String

    var body: some View {
        Group {
            switch summary {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Summarizing…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("timeline_progress_summary_\(label)")
            case let .finished(result):
                ChangeSummaryView(summary: result, ids: .init(
                    keyPoints: "timeline_list_summaryKeyPoints_\(label)",
                    text: "timeline_label_summary_\(label)",
                    generated: "timeline_label_summaryGenerated_\(label)"
                ))
            case .unavailable:
                Text("Summary unavailable")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("timeline_label_summaryUnavailable_\(label)")
            }
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline_card_summary_\(label)")
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
                    .accessibilityIdentifier("timelineFilter_button_showAll")
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
                        .accessibilityIdentifier("timelineFilter_button_type\(type.rawValue)")
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
                    .accessibilityIdentifier("timelineFilter_button_done")
                }
            }
        }
        .accessibilityIdentifier("screen_timelineFilter")
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    TimelineView(env: .live())
}
