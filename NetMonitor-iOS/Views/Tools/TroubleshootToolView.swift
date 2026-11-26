import SwiftUI
import SwiftData
import UIKit
import NetMonitorCore

/// Tools ▸ Troubleshoot (#451): describe a symptom or pick one, watch the app's fixed checks run,
/// then read the ranked likely causes and, when the model is available, its explanation.
/// Pushed inside `ToolsView`'s navigation stack, so it has none of its own.
struct TroubleshootToolView: View {
    @State private var viewModel: TroubleshootToolViewModel
    @State private var symptom = ""
    @State private var host = ""
    @Query private var devices: [LocalDevice]
    /// Only the latest saved test: its download is the baseline.
    @Query private var speedTests: [SpeedTestResult]
    private let networkProfileID: UUID?

    init(env: AppEnvironment) {
        _viewModel = State(initialValue: TroubleshootToolViewModel(env: env))
        networkProfileID = env.currentNetworkProfileID()
        var latest = FetchDescriptor<SpeedTestResult>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        latest.fetchLimit = 1
        _speedTests = Query(latest)
    }

    private var state: TroubleshootState { viewModel.state }

    /// What the state reads when a run needs it: the devices as the troubleshooter sees them (a
    /// rename or a scan's new ports change them) and the latest saved speed test.
    private struct InputsKey: Equatable {
        let devices: [TroubleshootDevice]
        let latestSpeedTest: UUID?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
                symptomSection
                promptSection
                if !state.steps.isEmpty {
                    stepsSection
                }
                if !state.findings.isEmpty {
                    findingsSection
                }
                explanationSection
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .scrollDismissesKeyboard(.interactively)
        .themedBackground()
        .navigationTitle("Troubleshoot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .accessibilityIdentifier("screen_troubleshootTool")
        .task(id: InputsKey(
            devices: TroubleshootToolViewModel.devices(devices, networkProfileID: networkProfileID), latestSpeedTest: speedTests.first?.id
        )) {
            viewModel.update(devices: devices, networkProfileID: networkProfileID, latestDownload: speedTests.first?.downloadSpeed)
        }
        .onDisappear { state.cancel() }
    }

    // MARK: - Symptom

    private var symptomSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What's wrong?")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            if state.canDescribe {
                ToolInputField(
                    text: $symptom,
                    placeholder: "Zoom keeps freezing",
                    icon: "bubble.left",
                    autocapitalization: .sentences,
                    accessibilityID: "troubleshoot_field_symptom",
                    onSubmit: start
                )
                .disabled(state.isRunning)
                ToolRunButton(
                    title: "Start",
                    icon: "stethoscope",
                    isRunning: state.isRunning,
                    stopTitle: "Cancel",
                    action: { state.isRunning ? state.cancel() : start() }
                )
                .disabled(!state.isRunning && symptom.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier(state.isRunning ? "troubleshoot_button_cancel" : "troubleshoot_button_start")
                Text("Or pick one:")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else if state.isRunning {
                ToolRunButton(title: "Start", icon: "stethoscope", isRunning: true, stopTitle: "Cancel") { state.cancel() }
                    .accessibilityIdentifier("troubleshoot_button_cancel")
            }
            kindButtons
        }
    }

    private var kindButtons: some View {
        VStack(spacing: 8) {
            ForEach(SymptomKind.pickable, id: \.self) { kind in
                Button {
                    symptom = ""
                    Task { await state.choose(kind) }
                } label: {
                    Text(kind.title)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .glassCard()
                }
                .buttonStyle(.plain)
                .disabled(state.isRunning)
                .accessibilityIdentifier("troubleshoot_button_kind_\(kind.rawValue)")
            }
        }
    }

    private func start() {
        let text = symptom
        dismissKeyboard()
        Task { await state.describe(text) }
    }

    /// The keyboard would cover the steps as they run.
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Prompts

    @ViewBuilder
    private var promptSection: some View {
        switch state.phase {
        case .unsupported:
            message(TroubleshootState.unsupportedMessage)
        case let .stopped(text):
            message(text)
        case let .needsDevice(candidates):
            VStack(alignment: .leading, spacing: 8) {
                Text("Which device?")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, device in
                    Button {
                        Task { await state.pick(device) }
                    } label: {
                        Text(device.displayName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .glassCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("troubleshoot_button_device_\(index + 1)")
                }
            }
        case .needsHost:
            VStack(alignment: .leading, spacing: 8) {
                ToolInputField(text: $host, placeholder: "example.com", icon: "globe", keyboardType: .URL,
                               accessibilityID: "troubleshoot_field_host") { checkHost() }
                Button("Check this website", action: checkHost)
                    .disabled(TroubleshootState.hostName(host) == nil)
                    .accessibilityIdentifier("troubleshoot_button_checkHost")
            }
        default:
            EmptyView()
        }
    }

    private func checkHost() {
        let text = host
        dismissKeyboard()
        Task { await state.useHost(text) }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("troubleshoot_label_message")
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(state.kind?.title ?? "Checks")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if state.canSkipCurrentStep {
                    Button("Skip") { state.skipCurrentStep() }
                        .font(.subheadline)
                        .accessibilityIdentifier("troubleshoot_button_skip")
                }
            }
            if let room = state.intent?.room {
                Text("Where: \(room)")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            ForEach(state.steps) { step in
                stepRow(step)
            }
            if let note = state.kind.flatMap(TroubleshootScript.note(for:)) {
                Label(note, systemImage: "wifi")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("troubleshoot_label_note")
            }
        }
        .glassCard()
    }

    private func stepRow(_ step: TroubleshootStep) -> some View {
        HStack(alignment: .top, spacing: 10) {
            stepIcon(step.status)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(step.id). \(step.check.title)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(step.status.text)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("troubleshoot_step_\(step.id)")
    }

    /// The icon for a step's tone (Core `TroubleshootStep.Status.tone`).
    @ViewBuilder
    private func stepIcon(_ status: TroubleshootStep.Status) -> some View {
        switch status.tone {
        case .pending: Image(systemName: "circle").foregroundStyle(Theme.Colors.textTertiary)
        case .running: ProgressView().controlSize(.small)
        case .unmeasured: Image(systemName: "minus.circle").foregroundStyle(Theme.Colors.textSecondary)
        case .measured: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Colors.success)
        case .cancelled: Image(systemName: "xmark.circle").foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    // MARK: - Findings

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.phase == .finished ? "Likely causes" : "Found so far")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            ForEach(Array(state.findings.enumerated()), id: \.element.id) { index, finding in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(index + 1). \(finding.title)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(finding.kind == .noProblem ? Theme.Colors.success : Theme.Colors.warning)
                    Text(finding.detail)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(finding.nextStep, systemImage: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("troubleshoot_finding_\(index + 1)")
            }
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("troubleshoot_list_findings")
    }

    // MARK: - Explanation

    @ViewBuilder
    private var explanationSection: some View {
        if state.isExplaining {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Writing an explanation…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        } else if let text = state.explanation {
            VStack(alignment: .leading, spacing: 8) {
                Label("Explanation", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("troubleshoot_label_explanation")
                Text("Written by \(state.explanationSource.modelName) from the likely causes above. Check it against them.")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("troubleshoot_label_generated")
            }
            .glassCard()
        }
    }
}
