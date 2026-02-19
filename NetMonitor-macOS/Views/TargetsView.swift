import SwiftUI
import NetMonitorCore
import SwiftData
import os

struct TargetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MonitoringSession.self) private var monitoringSession: MonitoringSession?
    @Query(sort: \NetworkTarget.name) private var targets: [NetworkTarget]

    @State private var showingAddSheet = false
    @State private var selectedTarget: NetworkTarget?
    @State private var sortOption: TargetSortOption = .name
    @State private var targetToDelete: NetworkTarget?
    @State private var showDeleteConfirmation = false

    var sortedTargets: [NetworkTarget] {
        switch sortOption {
        case .name:
            return targets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .status:
            return targets.sorted { lhs, rhs in
                let lhsOnline = monitoringSession?.latestMeasurement(for: lhs.id)?.isReachable ?? false
                let rhsOnline = monitoringSession?.latestMeasurement(for: rhs.id)?.isReachable ?? false
                if lhsOnline != rhsOnline {
                    return lhsOnline  // Online first
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .protocol:
            return targets.sorted { lhs, rhs in
                if lhs.targetProtocol != rhs.targetProtocol {
                    return lhs.targetProtocol.rawValue < rhs.targetProtocol.rawValue
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    var body: some View {
        VStack {
            if targets.isEmpty {
                ContentUnavailableView(
                    "No Targets",
                    systemImage: "target",
                    description: Text("Add network targets to monitor")
                )
                .accessibilityIdentifier("targets_label_empty")
            } else {
                List(selection: $selectedTarget) {
                    ForEach(sortedTargets) { target in
                        TargetRow(target: target, monitoringSession: monitoringSession)
                            .tag(target)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    target.isEnabled.toggle()
                                    do {
                                        try modelContext.save()
                                    } catch {
                                        Logger.data.error("Failed to save target enabled state: \(error)")
                                    }
                                } label: {
                                    Label(target.isEnabled ? "Disable" : "Enable",
                                          systemImage: target.isEnabled ? "pause.circle" : "play.circle")
                                }
                                .tint(target.isEnabled ? .orange : .green)
                            }
                            .accessibilityIdentifier("targets_row_\(target.id)")
                            .contextMenu {
                                Button(role: .destructive) {
                                    targetToDelete = target
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete Target", systemImage: "trash")
                                }
                                .accessibilityIdentifier("targets_menu_delete")
                            }
                    }
                    .onDelete(perform: deleteTargets)
                }
            }
        }
        .navigationTitle("Targets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddSheet = true }) {
                    Label("Add Target", systemImage: "plus")
                }
                .accessibilityIdentifier("targets_button_add")
            }
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) {
                    if let selected = selectedTarget {
                        targetToDelete = selected
                        showDeleteConfirmation = true
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedTarget == nil)
                .accessibilityIdentifier("targets_button_delete")
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Picker("Sort By", selection: $sortOption) {
                        ForEach(TargetSortOption.allCases) { option in
                            Label(option.rawValue, systemImage: option.iconName)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityIdentifier("targets_menu_sort")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddTargetSheet()
        }
        .confirmationDialog("Delete Target?", isPresented: $showDeleteConfirmation, presenting: targetToDelete) { target in
            Button("Delete", role: .destructive) {
                deleteTarget(target)
            }
            Button("Cancel", role: .cancel) { }
        } message: { target in
            Text("This will permanently delete '\(target.name)' and all its measurement history.")
        }
    }

    private func deleteTargets(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sortedTargets[index])
        }
        do {
            try modelContext.save()
        } catch {
            Logger.data.error("Error deleting targets: \(error, privacy: .public)")
        }
    }

    private func deleteTarget(_ target: NetworkTarget) {
        modelContext.delete(target)

        // Clear selection if deleted target was selected
        if selectedTarget?.id == target.id {
            selectedTarget = nil
        }

        do {
            try modelContext.save()
        } catch {
            Logger.data.error("Error deleting target: \(error, privacy: .public)")
        }
    }
}

enum TargetSortOption: String, CaseIterable, Identifiable {
    case name = "Name"
    case status = "Status"
    case `protocol` = "Protocol"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .name: return "textformat"
        case .status: return "checkmark.circle"
        case .protocol: return "network"
        }
    }
}

struct TargetRow: View {
    @Bindable var target: NetworkTarget
    var monitoringSession: MonitoringSession?

    var statusColor: Color {
        guard let measurement = monitoringSession?.latestMeasurement(for: target.id) else {
            return .gray
        }
        return measurement.isReachable ? .green : .red
    }

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(target.name)
                    .font(.headline)

                Text(target.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                Label(target.targetProtocol.rawValue, systemImage: target.targetProtocol.iconName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Enabled", isOn: $target.isEnabled)
                    .labelsHidden()
                    .accessibilityIdentifier("targets_toggle_enabled_\(target.id)")
            }
        }
        .padding(.vertical, 4)
    }
}

#if DEBUG
#Preview {
    TargetsView()
        .modelContainer(PreviewContainer().container)
}
#endif
