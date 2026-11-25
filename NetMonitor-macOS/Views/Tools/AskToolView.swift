//
//  AskToolView.swift
//  NetMonitor
//
//  Tools ▸ Ask (#452): ask about the saved devices and the Timeline in plain words. The on-device
//  model looks the answer up with the app's tools; the devices and events those returned are
//  listed below it and open their records.
//

import SwiftUI
import SwiftData
import NetMonitorCore

struct AskToolView: View {
    @Environment(NetworkProfileManager.self) private var profileManager: NetworkProfileManager?
    @Environment(DeviceDiscoveryCoordinator.self) private var coordinator: DeviceDiscoveryCoordinator?
    @Query private var devices: [LocalDevice]
    @State private var viewModel = AskMacViewModel()
    @State private var question = ""
    @State private var openDevice: LocalDevice?
    @State private var openEvent: AskAnswer.EventCitation?

    private var state: AskState { viewModel.state }
    private var networkProfileID: UUID? { profileManager?.localProfile?.id ?? profileManager?.activeProfile?.id }
    private var lastScan: Date? { coordinator?.lastScanTime(for: networkProfileID) }

    /// What the state reads when a question is asked: a rename or a scan changes it.
    private struct InputsKey: Equatable {
        let names: [String]
        let addresses: [String]
        let networkProfileID: UUID?
        let lastScan: Date?
        let isScanning: Bool
    }

    var body: some View {
        ToolSheetContainer(
            title: "Ask",
            iconName: NetworkTool.ask.iconName,
            closeAccessibilityID: "ask_button_close",
            minWidth: 600,
            minHeight: 460,
            inputArea: { inputArea },
            outputArea: { output },
            footerContent: { footer }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen_ask")
        .task(id: InputsKey(
            names: devices.map(\.displayName),
            addresses: devices.map(\.ipAddress),
            networkProfileID: networkProfileID,
            lastScan: lastScan,
            isScanning: coordinator?.isScanning ?? false
        )) {
            viewModel.update(
                devices: devices, networkProfileID: networkProfileID, lastScan: lastScan, isScanning: coordinator?.isScanning ?? false
            )
        }
        .sheet(item: $openDevice) { device in
            ProDeviceDetailView(device: device)
                .frame(minWidth: 700, minHeight: 500)
        }
        .sheet(item: $openEvent) { event in
            TimelineView(focusDay: event.timestamp)
                .frame(minWidth: 520, minHeight: 420)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { openEvent = nil }
                            .accessibilityIdentifier("ask_button_closeTimeline")
                    }
                }
        }
        .onDisappear { state.cancel() }
    }

    // MARK: - Input

    private var inputArea: some View {
        HStack(spacing: 8) {
            TextField("Ask about your network. For example: Is the printer up?", text: $question)
                .textFieldStyle(.roundedBorder)
                .onSubmit(ask)
                .disabled(state.isAsking)
                .accessibilityIdentifier("ask_field_question")
            if state.isAsking {
                Button("Cancel") { state.cancel() }
                    .accessibilityIdentifier("ask_button_cancel")
            } else {
                Button("Ask", action: ask)
                    .keyboardShortcut(.defaultAction)
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("ask_button_ask")
            }
        }
    }

    private func ask() {
        let text = question
        Task { await state.ask(text) }
    }

    // MARK: - Output

    private var output: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                phase
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var phase: some View {
        switch state.phase {
        case .idle:
            Text("Ask about the devices and events NetMonitor has saved, such as what joined this week or which devices have been flaky.")
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.Colors.labelSecondary)
        case .asking:
            ProgressView("Looking it up…").controlSize(.small)
        case let .needsDevice(candidates):
            VStack(alignment: .leading, spacing: 6) {
                Text("Which device?")
                    .font(.headline)
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, device in
                    Button(device.displayName) {
                        Task { await state.pick(device) }
                    }
                    .accessibilityIdentifier("ask_button_device_\(index + 1)")
                }
            }
        case let .stopped(text):
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.Colors.textSecondary)
                .accessibilityIdentifier("ask_label_message")
        case let .answered(answer):
            answerCard(answer)
            if !answer.devices.isEmpty || !answer.events.isEmpty {
                citations(answer)
            }
        }
    }

    private func answerCard(_ answer: AskAnswer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(answer.shownText)
                .font(.system(size: 13))
                .foregroundStyle(MacTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("ask_label_answer")
            if let freshness = answer.freshness {
                // The app's own line: the model may leave out how old the statuses are.
                Label(freshness, systemImage: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("ask_label_freshness")
            }
            if answer.text != nil {
                Label("Written by the on-device model from the records below", systemImage: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("ask_label_generated")
            }
        }
        .macGlassCard(cornerRadius: 12, padding: 10, statusGlow: MacTheme.Colors.info)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ask_card_answer")
    }

    // MARK: - Citations

    private func citations(_ answer: AskAnswer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Looked up")
                .font(.headline)
                .foregroundStyle(MacTheme.Colors.textPrimary)
            ForEach(Array(answer.devices.enumerated()), id: \.element.id) { index, citation in
                let device = viewModel.device(for: citation)
                Button {
                    // Found by id, so a renamed device still opens.
                    openDevice = device
                } label: {
                    // Last seen, so a stale answer's "last-seen times are below" holds.
                    // The app's status and last seen: the model's text never states presence.
                    Label(
                        [
                            device?.displayName ?? citation.name, citation.presence.label,
                            "last seen " + citation.lastSeen.formatted(.relative(presentation: .named))
                        ].joined(separator: " · "),
                        systemImage: device?.deviceType.iconName ?? "questionmark.circle"
                    )
                    .font(.system(size: 12))
                }
                .buttonStyle(.link)
                .disabled(device == nil)
                .accessibilityIdentifier("ask_citation_device_\(index + 1)")
            }
            ForEach(Array(answer.events.enumerated()), id: \.element.id) { index, event in
                Button {
                    openEvent = event
                } label: {
                    Label("\(event.title) · \(event.timestamp.formatted(date: .abbreviated, time: .shortened))",
                          systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("ask_citation_event_\(index + 1)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macGlassCard(cornerRadius: 12, padding: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ask_list_citations")
    }

    private var footer: some View {
        Text("Answers come only from what the app has saved; numbers and names the lookups didn't return are not shown. "
            + "Nothing is asked during a device scan.")
            .font(.caption)
            .foregroundStyle(MacTheme.Colors.labelSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .accessibilityIdentifier("ask_label_footer")
    }
}
