//
//  TroubleshootToolView.swift
//  NetMonitor
//
//  Tools ▸ Troubleshoot (#451): describe a symptom or pick one, watch the app's fixed checks run,
//  then read the ranked likely causes and, when the model is available, its explanation.
//

import SwiftUI
import SwiftData
import NetMonitorCore

struct TroubleshootToolView: View {
    @Environment(NetworkProfileManager.self) private var profileManager: NetworkProfileManager?
    @Environment(DeviceDiscoveryCoordinator.self) private var coordinator: DeviceDiscoveryCoordinator?
    @Query private var devices: [LocalDevice]
    @State private var viewModel = TroubleshootMacViewModel()
    @State private var symptom = ""
    @State private var host = ""

    private var state: TroubleshootState { viewModel.state }
    private var networkProfileID: UUID? { profileManager?.localProfile?.id ?? profileManager?.activeProfile?.id }

    /// What the state reads when a run needs it.
    private struct InputsKey: Equatable {
        let devices: [TroubleshootDevice]
        let networkProfileID: UUID?
        let isScanning: Bool
    }

    var body: some View {
        ToolSheetContainer(
            title: "Troubleshoot",
            iconName: NetworkTool.troubleshoot.iconName,
            closeAccessibilityID: "troubleshoot_button_close",
            minWidth: 640,
            minHeight: 520,
            inputArea: { inputArea },
            outputArea: { output },
            footerContent: { footer }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen_troubleshoot")
        .task(id: InputsKey(
            devices: DeviceGroups.project(devices).map(TroubleshootDevice.init),
            networkProfileID: networkProfileID,
            isScanning: coordinator?.isScanning ?? false
        )) {
            viewModel.update(devices: devices, networkProfileID: networkProfileID, isScanning: coordinator?.isScanning ?? false)
        }
        .onDisappear { state.cancel() }
    }

    // MARK: - Input

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.canDescribe {
                HStack(spacing: 8) {
                    TextField("What's wrong? For example: Zoom keeps freezing", text: $symptom)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(start)
                        .disabled(state.isRunning)
                        .accessibilityIdentifier("troubleshoot_field_symptom")
                    if state.isRunning {
                        Button("Cancel") { state.cancel() }
                            .accessibilityIdentifier("troubleshoot_button_cancel")
                    } else {
                        Button("Start", action: start)
                            .keyboardShortcut(.defaultAction)
                            .disabled(symptom.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("troubleshoot_button_start")
                    }
                }
            } else if state.isRunning {
                Button("Cancel") { state.cancel() }
                    .accessibilityIdentifier("troubleshoot_button_cancel")
            }
            HStack(spacing: 6) {
                Text(state.canDescribe ? "Or pick one:" : "What's wrong?")
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                ForEach(SymptomKind.pickable, id: \.self) { kind in
                    Button(kind.title) {
                        symptom = ""
                        Task { await state.choose(kind) }
                    }
                    .controlSize(.small)
                    .disabled(state.isRunning)
                    .accessibilityIdentifier("troubleshoot_button_kind_\(kind.rawValue)")
                }
            }
        }
    }

    private func start() {
        let text = symptom
        Task { await state.describe(text) }
    }

    // MARK: - Output

    private var output: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                prompt
                if !state.steps.isEmpty {
                    stepsCard
                }
                if !state.findings.isEmpty {
                    findingsCard
                }
                explanation
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var prompt: some View {
        switch state.phase {
        case .idle:
            Text("Describe the problem or pick one above. The app runs a fixed set of checks and shows each result.")
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.Colors.labelSecondary)
        case .classifying:
            ProgressView("Reading the symptom…").controlSize(.small)
        case .unsupported:
            message(TroubleshootState.unsupportedMessage)
        case let .stopped(text):
            message(text)
        case let .needsDevice(candidates):
            VStack(alignment: .leading, spacing: 6) {
                Text("Which device?")
                    .font(.headline)
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, device in
                    Button(device.displayName) {
                        Task { await state.pick(device) }
                    }
                    .accessibilityIdentifier("troubleshoot_button_device_\(index + 1)")
                }
            }
        case .needsHost:
            HStack(spacing: 8) {
                TextField("Website, such as example.com", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(checkHost)
                    .accessibilityIdentifier("troubleshoot_field_host")
                Button("Check", action: checkHost)
                    .disabled(TroubleshootState.hostName(host) == nil)
                    .accessibilityIdentifier("troubleshoot_button_checkHost")
            }
        case .running, .finished:
            EmptyView()
        }
    }

    private func checkHost() {
        let text = host
        Task { await state.useHost(text) }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(MacTheme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("troubleshoot_label_message")
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(state.kind?.title ?? "Checks")
                    .font(.headline)
                    .foregroundStyle(MacTheme.Colors.textPrimary)
                if let room = state.intent?.room {
                    Text("· \(room)")
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.Colors.labelSecondary)
                }
                Spacer()
                if state.canSkipCurrentStep {
                    Button("Skip") { state.skipCurrentStep() }
                        .controlSize(.small)
                        .accessibilityIdentifier("troubleshoot_button_skip")
                }
            }
            ForEach(state.steps) { step in
                HStack(alignment: .top, spacing: 8) {
                    stepIcon(step.status)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(step.id). \(step.check.title)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MacTheme.Colors.textPrimary)
                        Text(step.status.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MacTheme.Colors.labelSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("troubleshoot_step_\(step.id)")
            }
            if let note = state.kind.flatMap(TroubleshootScript.note(for:)) {
                Label(note, systemImage: "wifi")
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                    .accessibilityIdentifier("troubleshoot_label_note")
            }
        }
        .macGlassCard(cornerRadius: 12, padding: 10)
        .accessibilityElement(children: .contain)
    }

    /// The icon for a step's tone (Core `TroubleshootStep.Status.tone`).
    @ViewBuilder
    private func stepIcon(_ status: TroubleshootStep.Status) -> some View {
        switch status.tone {
        case .pending: Image(systemName: "circle").foregroundStyle(MacTheme.Colors.labelTertiary)
        case .running: ProgressView().controlSize(.mini)
        case .unmeasured: Image(systemName: "minus.circle").foregroundStyle(MacTheme.Colors.labelSecondary)
        case .measured: Image(systemName: "checkmark.circle.fill").foregroundStyle(MacTheme.Colors.success)
        case .cancelled: Image(systemName: "xmark.circle").foregroundStyle(MacTheme.Colors.labelTertiary)
        }
    }

    private var findingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.phase == .finished ? "Likely causes" : "Found so far")
                .font(.headline)
                .foregroundStyle(MacTheme.Colors.textPrimary)
            ForEach(Array(state.findings.enumerated()), id: \.element.id) { index, finding in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(index + 1). \(finding.title)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(finding.kind == .noProblem ? MacTheme.Colors.success : MacTheme.Colors.warning)
                    Text(finding.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(finding.nextStep, systemImage: "arrow.right.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("troubleshoot_finding_\(index + 1)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macGlassCard(cornerRadius: 12, padding: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("troubleshoot_list_findings")
    }

    @ViewBuilder
    private var explanation: some View {
        if state.isExplaining {
            ProgressView("Writing an explanation…").controlSize(.small)
        } else if let text = state.explanation {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.Colors.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("troubleshoot_label_explanation")
                Label("Written by the on-device model from the likely causes above", systemImage: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("troubleshoot_label_generated")
            }
            .macGlassCard(cornerRadius: 12, padding: 10, statusGlow: MacTheme.Colors.info)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("troubleshoot_card_explanation")
        }
    }

    private var footer: some View {
        Text("The app picks and runs every check; findings come from fixed thresholds. Nothing runs during a device scan.")
            .font(.caption)
            .foregroundStyle(MacTheme.Colors.labelSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .accessibilityIdentifier("troubleshoot_label_footer")
    }
}
