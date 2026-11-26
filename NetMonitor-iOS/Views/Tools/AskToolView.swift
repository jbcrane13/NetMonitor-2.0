import SwiftUI
import SwiftData
import UIKit
import NetMonitorCore

/// Tools ▸ Ask (#452): ask about the saved devices and the Timeline in plain words. The on-device
/// model looks the answer up with the app's tools; the devices and events those returned are
/// listed below it and open their records. Pushed inside `ToolsView`'s navigation stack, so it
/// has none of its own.
struct AskToolView: View {
    @State private var viewModel: AskToolViewModel
    @State private var question = ""
    /// The cited device's `LocalDevice.id`: detail opens the saved row, not whatever answers at its address now.
    @State private var openDevice: UUID?
    @State private var openEvent: AskAnswer.EventCitation?
    @Environment(\.modelContext) private var modelContext
    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
        _viewModel = State(initialValue: AskToolViewModel(env: env))
    }

    private var state: AskState { viewModel.state }

    /// The devices Ask reads: every network's most recent, paged by device, each with every member
    /// (#594); the snapshot keeps the current network's when a question is asked.
    private func readDevices() {
        let devices = (try? DeviceGroups.recentDevices(in: .allNetworks, limit: AskIntentRunner.deviceLimit, in: modelContext)) ?? []
        viewModel.update(devices: devices.flatMap(\.members))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
                questionSection
                phaseSection
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .scrollDismissesKeyboard(.interactively)
        .themedBackground()
        .navigationTitle("Ask")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .accessibilityIdentifier("screen_ask")
        // A rename or a scan changes what the tools read: read again after every save.
        .task { readDevices() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { _ in
            readDevices()
        }
        .navigationDestination(item: $openDevice) { id in
            DeviceDetailView(deviceID: id)
        }
        .sheet(item: $openEvent) { event in
            TimelineView(env: env, focusDay: event.timestamp)
        }
        .onDisappear { state.cancel() }
    }

    // MARK: - Question

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask about your network")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            ToolInputField(
                text: $question,
                placeholder: "Is the printer up?",
                icon: "questionmark.bubble",
                autocapitalization: .sentences,
                accessibilityID: "ask_field_question",
                onSubmit: ask
            )
            .disabled(state.isAsking)
            if state.isAsking {
                ToolRunButton(title: "Ask", icon: "sparkles", isRunning: true, stopTitle: "Cancel") { state.cancel() }
                    .accessibilityIdentifier("ask_button_cancel")
            } else {
                ToolRunButton(title: "Ask", icon: "sparkles", isRunning: false, action: ask)
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("ask_button_ask")
            }
            Text("Answers come from the devices and events NetMonitor has saved, and pings it makes when asked.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func ask() {
        let text = question
        // The keyboard would cover the answer.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { await state.ask(text) }
    }

    // MARK: - Phases

    @ViewBuilder
    private var phaseSection: some View {
        switch state.phase {
        case .idle:
            EmptyView()
        case .asking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking it up…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
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
                    .accessibilityIdentifier("ask_button_device_\(index + 1)")
                }
            }
        case let .stopped(text):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("ask_label_message")
        case let .answered(answer):
            answerCard(answer)
            if !answer.devices.isEmpty || !answer.events.isEmpty {
                citations(answer)
            }
        }
    }

    private func answerCard(_ answer: AskAnswer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Answer", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(answer.shownText)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ask_label_answer")
            // The app's live measurements (#579), in its own words: the model's never state them.
            ForEach(Array(answer.measurements.enumerated()), id: \.element.id) { index, measurement in
                Label(
                    "\(measurement.text), measured at \(measurement.measuredAt.formatted(date: .omitted, time: .shortened))",
                    systemImage: measurement.deviceID == nil ? "network" : "dot.radiowaves.left.and.right"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ask_label_measurement_\(index + 1)")
            }
            if let freshness = answer.freshness {
                // The app's own line: the model may leave out how old the statuses are.
                Label(freshness, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ask_label_freshness")
            }
            if answer.text != nil {
                Text("Written by the on-device model from the records below. Check it against them.")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("ask_label_generated")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Citations

    private func citations(_ answer: AskAnswer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Looked up")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            ForEach(Array(answer.devices.enumerated()), id: \.element.id) { index, citation in
                Button {
                    open(citation)
                } label: {
                    let device = viewModel.device(for: citation)
                    citationRow(
                        icon: device?.deviceType.iconName ?? "questionmark.circle",
                        title: device?.displayName ?? citation.name,
                        detail: "Last seen " + citation.lastSeen.formatted(.relative(presentation: .named)),
                        presence: citation.presence
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ask_citation_device_\(index + 1)")
            }
            ForEach(Array(answer.events.enumerated()), id: \.element.id) { index, event in
                Button {
                    openEvent = event
                } label: {
                    citationRow(icon: "clock.arrow.circlepath", title: event.title,
                                detail: event.timestamp.formatted(date: .abbreviated, time: .shortened))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ask_citation_event_\(index + 1)")
            }
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ask_list_citations")
    }

    private func citationRow(icon: String, title: String, detail: String?, presence: PresenceFreshness? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if let presence {
                // The app's status: the model's text never states presence.
                Text(presence.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(presence == .online ? Theme.Colors.success : Theme.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.Colors.textSecondary.opacity(0.15)))
                    .accessibilityIdentifier("ask_label_status")
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Opens the cited device's saved row by its id, so a renamed device still opens and a device
    /// now at its old address doesn't.
    private func open(_ citation: AskAnswer.DeviceCitation) {
        guard let device = viewModel.device(for: citation) else { return }
        openDevice = device.id
    }
}
