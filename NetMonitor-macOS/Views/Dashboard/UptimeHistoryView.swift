import SwiftUI
import SwiftData
import NetMonitorCore

/// Full uptime history view — presented as a sheet from ISPHealthCard.
struct UptimeHistoryView: View {
    let profileID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var vm: UptimeViewModel?
    @State private var recentOutages: [ConnectivityRecord] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                uptimeSummarySection
                outageLogSection
            }
            .padding(20)
        }
        .navigationTitle("Uptime History")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityIdentifier("uptimeHistory_button_close")
            }
        }
        .onAppear {
            if vm == nil {
                let viewModel = UptimeViewModel(
                    profileID: profileID,
                    modelContext: modelContext,
                    windowDays: 30,
                    barSegments: 30
                )
                viewModel.load()
                vm = viewModel
                loadRecentOutages()
            }
        }
    }

    // MARK: - Uptime Summary

    private var uptimeSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("30-Day Uptime", systemImage: "chart.bar.fill")
                .font(.headline)

            if let pct = vm?.uptimePct {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.2f%%", pct))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(pct > 99 ? MacTheme.Colors.success : MacTheme.Colors.warning)
                    Text("\(vm?.outageCount ?? 0) outage\(vm?.outageCount == 1 ? "" : "s")")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No history recorded yet")
                    .foregroundStyle(.secondary)
            }

            if let bar = vm?.uptimeBar, !bar.isEmpty {
// swiftlint:disable:next identifier_name
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(0..<bar.count, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    bar[i]
                                        ? MacTheme.Colors.success.opacity(0.7)
                                        : MacTheme.Colors.error
                                )
                                .frame(
                                    width: max(
                                        1,
                                        (g.size.width - CGFloat(bar.count - 1) * 2) / CGFloat(bar.count)
                                    )
                                )
                        }
                    }
                }
                .frame(height: 24)

                HStack {
                    Text("30 days ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
        .accessibilityIdentifier("uptimeHistory_section_summary")
    }

    // MARK: - Outage Log

    private var outageLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Outage Log", systemImage: "exclamationmark.triangle")
                .font(.headline)

            if recentOutages.isEmpty {
                Text("No outages recorded in the last 30 days")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(recentOutages, id: \.id) { record in
                    HStack {
                        Circle()
                            .fill(record.isOnline ? MacTheme.Colors.success : MacTheme.Colors.error)
                            .frame(width: 8, height: 8)
                        Text(record.isOnline ? "Came online" : "Went offline")
                        Spacer()
                        Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
        .accessibilityIdentifier("uptimeHistory_section_outageLog")
    }

    // MARK: - Private

    private func loadRecentOutages() {
        let since = Date().addingTimeInterval(-30 * 86400)
        let id = profileID
        var descriptor = FetchDescriptor<ConnectivityRecord>(
            predicate: #Predicate { $0.profileID == id && $0.timestamp >= since && !$0.isSample },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        recentOutages = (try? modelContext.fetch(descriptor)) ?? []
    }
}
