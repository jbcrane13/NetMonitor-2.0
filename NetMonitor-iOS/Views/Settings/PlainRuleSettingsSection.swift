import NetMonitorCore
import os
import SwiftData
import SwiftUI

/// Settings › Monitoring targets: "Describe a rule…" and the saved targets (#450).
///
/// The field shows only where the on-device model runs. The target list always shows, so a
/// target saved from a draft can be seen and removed. A port-scan draft sets `openPortScan`;
/// the screen presents the scanner, because a sheet on a list section is attached to every row.
struct PlainRuleSettingsSection: View {
    @Binding var openPortScan: PlainRuleIOSViewModel.PortScanRequest?
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var env: AppEnvironment?
    @Query private var devices: [LocalDevice]
    @Query(sort: \MonitoringTarget.createdAt) private var targets: [MonitoringTarget]
    @State private var viewModel = PlainRuleIOSViewModel()

    var body: some View {
        Section {
            if viewModel.isAvailable {
                describeField
                outcome
            }
            ForEach(targets) { target in
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(target.hostWithPort)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings_row_target_\(target.host)")
            }
            .onDelete(perform: deleteTargets)
            if targets.isEmpty {
                Text("No monitoring targets. Background refresh checks the ones you add and alerts when one goes down.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("settings_label_noTargets")
            }
        } header: {
            Text("Monitoring Targets")
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .listRowBackground(Theme.Colors.glassBackground)
    }

    private var describeField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Describe a rule…", text: $viewModel.text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.go)
                .onSubmit(parse)
                .accessibilityIdentifier("rules_field_describe")
            Button("Create Draft", action: parse)
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accent)
                .disabled(viewModel.text.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.composer.isWorking)
                .accessibilityIdentifier("rules_button_parse")
            if viewModel.composer.isWorking {
                ProgressView("Reading your rule…")
                    .accessibilityIdentifier("rules_draft_progress")
            }
        }
    }

    private func parse() {
        Task {
            await viewModel.submit(devices: devices, targets: targets, isScanning: env?.deviceDiscovery.isScanning ?? false)
        }
    }

    @ViewBuilder
    private var outcome: some View {
        switch viewModel.composer.outcome {
        case let .target(draft):
            draftCard(
                summary: "Add a monitoring target for \(draft.name) (\(draft.host))",
                notes: draft.notes,
                confirmTitle: "Confirm"
            ) { viewModel.confirm(context: modelContext) }
        case let .portScan(device, preset):
            draftCard(
                summary: "Scan \(preset.displayName.lowercased()) on \(device.displayName) (\(device.ipAddress))",
                notes: ["This opens the Port Scanner with these settings. Nothing is saved."],
                confirmTitle: "Open Port Scanner"
            ) { openPortScan = viewModel.takePortScan() }
        case let .pickDevice(candidates):
            VStack(alignment: .leading, spacing: 8) {
                Text("More than one device matches. Which one?")
                    .foregroundStyle(Theme.Colors.textPrimary)
                ForEach(candidates) { candidate in
                    Button("\(candidate.displayName) (\(candidate.ipAddress))") { viewModel.choose(candidate) }
                        // A non-plain style keeps each button's own tap inside one list row.
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("rules_draft_pick_\(candidate.id.uuidString)")
                }
            }
        case let .message(message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("rules_draft_message")
        case .alert, .none:
            EmptyView()
        }
    }

    private func draftCard(summary: String, notes: [String], confirmTitle: String, confirm: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Drafted by the on-device model from your words", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("rules_draft_marker")
            Text(summary)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("rules_draft_summary")
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("rules_draft_note")
            }
            HStack {
                Button("Cancel") { viewModel.cancel() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("rules_draft_cancel")
                Spacer()
                Button(confirmTitle, action: confirm)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.accent)
                    .accessibilityIdentifier("rules_button_confirm")
            }
        }
    }

    private func deleteTargets(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(targets[index])
        }
        do {
            try modelContext.save()
        } catch {
            Logger.data.error("Failed to delete monitoring targets: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The Port Scanner a described port-scan preset opens, prefilled (#450).
struct PlainRulePortScanSheet: View {
    let request: PlainRuleIOSViewModel.PortScanRequest
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            PortScannerToolView(initialHost: request.host, initialPreset: request.preset)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDone)
                            .accessibilityIdentifier("rules_button_closePortScan")
                    }
                }
        }
    }
}
