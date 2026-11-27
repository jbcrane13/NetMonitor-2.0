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
    @Binding var openPortScan: PortScanRequest?
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var env: AppEnvironment?
    @Query(Self.targetsDescriptor) private var targets: [MonitoringTarget]
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
            .onDelete { offsets in viewModel.delete(offsets.map { targets[$0] }, context: modelContext) }
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
                .accessibilityIdentifier("settings_field_describeRule")
            Button("Create Draft", action: parse)
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accent)
                .disabled(viewModel.text.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.composer.isWorking)
                .accessibilityIdentifier("settings_button_createRuleDraft")
            if viewModel.composer.isWorking {
                ProgressView("Reading your rule…")
                    .accessibilityIdentifier("settings_progress_ruleDraft")
            }
        }
    }

    private func parse() {
        let networkID = env?.currentNetworkProfileID()
        // The most recent devices, each with every member (#594).
        let scope = DeviceScope.network(networkID, else: .allNetworks)
        let devices = ((try? DeviceGroups.recentDevices(in: scope, limit: RuleDevice.candidateLimit, in: modelContext)) ?? [])
            .flatMap(\.members)
        // Devices scanned but never opened can be named too (#571), read now with the token they were
        // observed under: a row is saved from them only while it is current (#628).
        let scan = env?.deviceDiscovery.discoveredDevices ?? []
        let scanToken = env?.deviceDiscovery.discoveredDevicesToken
        Task {
            await viewModel.submit(
                devices: devices,
                scan: scan,
                scanToken: scanToken,
                targets: targets,
                networkID: networkID,
                isScanning: env?.deviceDiscovery.isScanning ?? false,
                context: modelContext
            )
        }
    }

    @ViewBuilder
    private var outcome: some View {
        if viewModel.isCheckingPorts {
            ProgressView("Checking ports…")
                .accessibilityIdentifier("settings_progress_ruleCheckingPorts")
        }
        switch viewModel.displayedOutcome {
        case .target:
            if let draft = viewModel.targetDraft {
                draftCard(
                    summary: "Add a monitoring target for \(draft.name) (\(draft.host))",
                    notes: draft.notes,
                    confirmTitle: "Confirm",
                    canConfirm: viewModel.canConfirmTarget && !viewModel.isCheckingPorts,
                    editor: targetEditor
                ) {
                    Task { await viewModel.confirm(context: modelContext, isScanning: env?.deviceDiscovery.isScanning ?? false) }
                }
            }
        case let .portScan(device, preset):
            draftCard(
                summary: "Scan \(preset.displayName.lowercased()) on \(device.displayName) (\(device.ipAddress))",
                notes: ["This opens the Port Scanner with these settings. Nothing is saved."],
                confirmTitle: "Open Port Scanner",
                editor: EmptyView()
            ) { openPortScan = viewModel.takePortScan() }
        case let .pickDevice(candidates):
            VStack(alignment: .leading, spacing: 8) {
                Text("More than one device matches. Which one?")
                    .foregroundStyle(Theme.Colors.textPrimary)
                ForEach(candidates) { candidate in
                    Button("\(candidate.displayName) (\(candidate.ipAddress))") { Task { await viewModel.choose(candidate) } }
                        // A non-plain style keeps each button's own tap inside one list row.
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("settings_button_ruleDevice_\(candidate.id.uuidString)")
                }
            }
        case let .message(message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("settings_label_ruleMessage")
        case .alert, .none:
            EmptyView()
        }
    }

    /// The target draft's name and address, editable before Confirm.
    private var targetEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name", text: targetBinding(\.name))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("settings_field_ruleTargetName")
            TextField("Address", text: targetBinding(\.host))
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("settings_field_ruleTargetHost")
        }
    }

    private func targetBinding(_ keyPath: WritableKeyPath<TargetDraft, String>) -> Binding<String> {
        Binding(
            get: { viewModel.targetDraft?[keyPath: keyPath] ?? "" },
            set: { viewModel.targetDraft?[keyPath: keyPath] = $0 }
        )
    }

    private func draftCard(
        summary: String,
        notes: [String],
        confirmTitle: String,
        canConfirm: Bool = true,
        editor: some View,
        confirm: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Drafted by the on-device model from your words", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("settings_label_ruleDraftMarker")
            Text(summary)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("settings_label_ruleDraftSummary")
            editor
            if let problem = viewModel.confirmProblem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.warning)
                    .accessibilityIdentifier("settings_label_ruleTargetProblem")
            }
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("settings_label_ruleDraftNote")
            }
            HStack {
                Button("Cancel") { viewModel.cancel() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("settings_button_cancelRuleDraft")
                Spacer()
                Button(confirmTitle, action: confirm)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.accent)
                    .disabled(!canConfirm)
                    .accessibilityIdentifier("settings_button_confirmRuleDraft")
            }
        }
    }

    /// Every target, uncapped: background refresh checks every enabled one, so each must have a
    /// row here to remove it. The list is small (one row per monitored host).
    private static var targetsDescriptor: FetchDescriptor<MonitoringTarget> {
        FetchDescriptor<MonitoringTarget>(sortBy: [SortDescriptor(\.createdAt)])
    }
}

/// The Port Scanner a described port-scan preset opens, prefilled (#450).
struct PlainRulePortScanSheet: View {
    let request: PortScanRequest
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            PortScannerToolView(initialHost: request.host, initialPreset: request.preset)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDone)
                            .accessibilityIdentifier("settings_button_closePortScan")
                    }
                }
        }
    }
}
