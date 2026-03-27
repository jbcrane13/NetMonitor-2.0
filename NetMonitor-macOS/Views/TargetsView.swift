import SwiftUI
import NetMonitorCore
import SwiftData
import os

struct TargetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MonitoringSession.self) private var monitoringSession: MonitoringSession?
    @Query(sort: \NetworkTarget.name) private var targets: [NetworkTarget]

    @State private var showingAddSheet = false
    @State private var selectedTargets: Set<NetworkTarget> = []
    @State private var sortOption: TargetSortOption = .name
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
                List(selection: $selectedTargets) {
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
                                .accessibilityIdentifier("targets_row_swipe_toggleEnabled_\(target.id)")
                            }
                            .accessibilityIdentifier("targets_row_\(target.id)")
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteTarget(target)
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
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete \(selectedTargets.count > 1 ? "\(selectedTargets.count) Targets" : "Target")", systemImage: "trash")
                }
                .disabled(selectedTargets.isEmpty)
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
        .confirmationDialog(
            selectedTargets.count == 1
                ? "Delete Target?"
                : "Delete \(selectedTargets.count) Targets?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedTargets()
            }
            .accessibilityIdentifier("targets_confirmDialog_button_delete")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("targets_confirmDialog_button_cancel")
        } message: {
            if selectedTargets.count == 1, let target = selectedTargets.first {
                Text("This will permanently delete '\(target.name)' and all its measurement history.")
            } else {
                Text("This will permanently delete \(selectedTargets.count) targets and all their measurement history.")
            }
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
        selectedTargets.remove(target)
        modelContext.delete(target)
        do {
            try modelContext.save()
        } catch {
            Logger.data.error("Error deleting target: \(error, privacy: .public)")
        }
    }

    private func deleteSelectedTargets() {
        for target in selectedTargets {
            modelContext.delete(target)
        }
        selectedTargets.removeAll()
        do {
            try modelContext.save()
        } catch {
            Logger.data.error("Error deleting targets: \(error, privacy: .public)")
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
