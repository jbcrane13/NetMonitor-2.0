//
//  PlainRuleSection.swift
//  NetMonitor
//
//  "Describe a rule…": a rule typed in plain English becomes a draft to review (#450).
//

import NetMonitorCore
import SwiftUI

struct PlainRuleSection: View {
    @Bindable var viewModel: PlainRuleMacViewModel
    let devices: [LocalDevice]
    let targets: [NetworkTarget]
    let isScanning: Bool
    let onConfirm: () -> Void

    var body: some View {
        SwiftUI.Section {
            HStack {
                TextField("Describe a rule", text: $viewModel.text, prompt: Text("Tell me if the NAS is down for more than five minutes"))
                    .onSubmit(parse)
                    .accessibilityIdentifier("rules_field_describe")
                Button("Create Draft", action: parse)
                    .disabled(viewModel.text.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.composer.isWorking)
                    .accessibilityIdentifier("rules_button_parse")
            }
            if viewModel.composer.isWorking {
                ProgressView("Reading your rule…")
                    .controlSize(.small)
                    .accessibilityIdentifier("rules_draft_progress")
            }
            outcome
        } header: {
            Text("Describe a rule…")
        } footer: {
            Text("The on-device model reads your words; the app finds the device and builds the draft. Nothing is saved until you confirm.")
        }
    }

    private func parse() {
        Task { await viewModel.submit(devices: devices, targets: targets, isScanning: isScanning) }
    }

    @ViewBuilder
    private var outcome: some View {
        switch viewModel.composer.outcome {
        case .alert:
            if viewModel.draft != nil {
                PlainRuleDraftView(viewModel: viewModel, onConfirm: onConfirm)
            }
        case let .portScan(device, preset):
            VStack(alignment: .leading, spacing: 6) {
                generatedMarker
                Text("Scan \(preset.displayName.lowercased()) on \(device.displayName) (\(device.ipAddress))")
                    .accessibilityIdentifier("rules_draft_summary")
                Text("This opens the Port Scanner with these settings. Nothing is saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                draftButtons(confirmTitle: "Open Port Scanner") {
                    viewModel.openPortScan = .init(host: device.ipAddress, preset: preset)
                    viewModel.cancel()
                }
            }
        case let .pickDevice(candidates):
            VStack(alignment: .leading, spacing: 6) {
                Text("More than one device matches. Which one?")
                    .accessibilityIdentifier("rules_draft_pickPrompt")
                ForEach(candidates) { candidate in
                    Button("\(candidate.displayName) (\(candidate.ipAddress))") { viewModel.choose(candidate) }
                        .accessibilityIdentifier("rules_draft_pick_\(candidate.id.uuidString)")
                }
            }
        case let .message(message):
            Label(message, systemImage: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("rules_draft_message")
        case .target, .none:
            EmptyView()
        }
    }

    private var generatedMarker: some View {
        Label("Drafted by the on-device model from your words", systemImage: "sparkles")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("rules_draft_marker")
    }

    private func draftButtons(confirmTitle: String, confirm: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button("Cancel") { viewModel.cancel() }
                .accessibilityIdentifier("rules_draft_cancel")
            Button(confirmTitle, action: confirm)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("rules_button_confirm")
        }
    }
}

/// The alert-rule draft, editable before Confirm.
private struct PlainRuleDraftView: View {
    @Bindable var viewModel: PlainRuleMacViewModel
    let onConfirm: () -> Void

    var body: some View {
        if let draft = viewModel.draft {
            VStack(alignment: .leading, spacing: 8) {
                Label("Drafted by the on-device model from your words", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("rules_draft_marker")
                TextField("Name", text: binding(\.rule.name))
                    .accessibilityIdentifier("rules_draft_name")
                LabeledContent("When", value: RuleDescription.trigger(draft.rule.trigger))
                    .accessibilityIdentifier("rules_draft_trigger")
                if case .latencyAbove = draft.rule.trigger {
                    Stepper("\(Int(latency)) ms", value: latencyBinding, in: 10...5000, step: 10)
                        .accessibilityIdentifier("rules_draft_latency")
                }
                if draft.rule.trigger == .wentOffline || draft.rule.trigger.isLatency {
                    Stepper(durationLabel, value: durationBinding, in: 0...1440)
                        .accessibilityIdentifier("rules_draft_duration")
                }
                if let device = draft.device {
                    LabeledContent("Device", value: "\(device.displayName) (\(device.ipAddress))")
                        .accessibilityIdentifier("rules_draft_device")
                }
                if draft.offersTarget, let device = draft.device {
                    Toggle("Also add a monitoring target for \(device.ipAddress)", isOn: $viewModel.addsTarget)
                        .accessibilityIdentifier("rules_draft_addTarget")
                }
                ForEach(viewModel.notes, id: \.self) { note in
                    Label(note, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("rules_draft_note")
                }
                HStack {
                    Spacer()
                    Button("Cancel") { viewModel.cancel() }
                        .accessibilityIdentifier("rules_draft_cancel")
                    Button("Confirm", action: onConfirm)
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.rule.name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("rules_button_confirm")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rules_draft_card")
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AlertRuleDraft, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.draft.map { $0[keyPath: keyPath] } ?? AlertRuleDraft.placeholder[keyPath: keyPath] },
            set: { viewModel.draft?[keyPath: keyPath] = $0 }
        )
    }

    private var latency: Double {
        if case let .latencyAbove(milliseconds) = viewModel.draft?.rule.trigger {
            return milliseconds
        }
        return Double(PlainRuleBuilder.defaultThreshold)
    }

    private var latencyBinding: Binding<Double> {
        Binding(get: { latency }, set: { viewModel.draft?.rule.trigger = .latencyAbove(milliseconds: $0) })
    }

    /// The minimum duration in whole minutes; 0 fires at once.
    private var durationBinding: Binding<Int> {
        Binding(
            get: { Int(((viewModel.draft?.rule.minimumDuration ?? 0) / 60).rounded()) },
            set: { viewModel.draft?.rule.minimumDuration = $0 > 0 ? TimeInterval($0 * 60) : nil }
        )
    }

    private var durationLabel: String {
        guard let seconds = viewModel.draft?.rule.minimumDuration, seconds > 0 else { return "At once" }
        return "For at least \(PlainRuleBuilder.spoken(seconds))"
    }
}

private extension AlertRuleTrigger {
    var isLatency: Bool {
        if case .latencyAbove = self {
            return true
        }
        return false
    }
}

private extension AlertRuleDraft {
    static let placeholder = AlertRuleDraft(
        rule: AlertRule(name: "", trigger: .wentOffline), device: nil, hasTarget: false, thresholdWasGiven: true
    )
}
