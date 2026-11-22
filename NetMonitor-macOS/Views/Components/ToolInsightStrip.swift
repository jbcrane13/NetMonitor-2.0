import NetMonitorCore
import SwiftUI

/// "Explain this result": a plain-language readout of a tool result from the on-device
/// language model (#448). Shows nothing when there is no result or the model is unavailable,
/// which includes every system before macOS 27.
struct ToolInsightStrip: View {
    /// Accessibility prefix, such as "whois".
    let screen: String
    /// The result to explain; nil hides the strip.
    let request: InsightRequest?
    /// False inside a card that already pads its content.
    let isInset: Bool
    @State private var state: ToolInsightState

    init(
        screen: String,
        request: InsightRequest?,
        isInset: Bool = true,
        service: any InsightServiceProtocol = InsightService.shared
    ) {
        self.screen = screen
        self.request = request
        self.isInset = isInset
        _state = State(initialValue: ToolInsightState(service: service))
    }

    var body: some View {
        if let request, state.isAvailable {
            VStack(alignment: .leading, spacing: 6) {
                content(for: request)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, isInset ? 16 : 0)
            .padding(.vertical, isInset ? 10 : 0)
            .accessibilityIdentifier("\(screen)_insight_card")
            .onDisappear { state.reset() }
        }
    }

    @ViewBuilder
    private func content(for request: InsightRequest) -> some View {
        switch state.phase(for: request) {
        case .idle:
            Button {
                state.explain(request)
            } label: {
                Label("Explain This Result", systemImage: "sparkles")
            }
            .accessibilityIdentifier("\(screen)_insight_button_explain")
        case let .generating(text):
            HStack(spacing: 8) {
                header
                ProgressView().controlSize(.small)
            }
            if !text.isEmpty {
                explanation(text)
                generatedNote
            }
        case let .finished(text):
            header
            explanation(text)
            generatedNote
        case .failed:
            HStack(spacing: 8) {
                Text("This result couldn't be explained.")
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                Button("Try Again") { state.explain(request) }
                    .accessibilityIdentifier("\(screen)_insight_button_retry")
            }
        }
    }

    private var generatedNote: some View {
            Text("Generated on this Mac. Check it against the result above.")
            .font(.caption)
            .foregroundStyle(MacTheme.Colors.labelTertiary)
            .accessibilityIdentifier("\(screen)_insight_label_generated")
    }

    private var header: some View {
        Label("Explanation", systemImage: "sparkles")
            .font(.headline)
    }

    private func explanation(_ text: String) -> some View {
        Text(text)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("\(screen)_insight_label_text")
    }
}
