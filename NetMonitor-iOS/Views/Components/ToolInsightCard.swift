import NetMonitorCore
import SwiftUI

/// "Explain this result": a plain-language readout of a tool result from the on-device
/// language model (#448). Shows nothing when there is no result or the model is unavailable,
/// which includes every system before iOS 27.
struct ToolInsightCard: View {
    /// Accessibility prefix, such as "whois".
    let screen: String
    /// The result to explain; nil hides the card.
    let request: InsightRequest?
    /// True inside another card, which already supplies the glass background.
    let isEmbedded: Bool
    @State private var state: ToolInsightState

    init(
        screen: String,
        request: InsightRequest?,
        isEmbedded: Bool = false,
        service: any InsightServiceProtocol = InsightService.shared
    ) {
        self.screen = screen
        self.request = request
        self.isEmbedded = isEmbedded
        _state = State(initialValue: ToolInsightState(service: service))
    }

    var body: some View {
        if let request, state.isAvailable {
            Group {
                if isEmbedded {
                    stack(for: request)
                } else {
                    stack(for: request).glassCard()
                }
            }
            .accessibilityIdentifier("\(screen)_insight_card")
            .onChange(of: request) { state.reset() }
        }
    }

    private func stack(for request: InsightRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content(for: request)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func content(for request: InsightRequest) -> some View {
        switch state.phase {
        case .idle:
            Button {
                state.explain(request)
            } label: {
                Label("Explain this result", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("\(screen)_insight_button_explain")
        case let .generating(text):
            HStack(spacing: 8) {
                header
                ProgressView().controlSize(.small)
            }
            if !text.isEmpty {
                explanation(text)
            }
        case let .finished(text):
            header
            explanation(text)
            Text("Generated on this device. Check it against the result above.")
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("\(screen)_insight_label_generated")
        case .failed:
            header
            Text("This result couldn't be explained.")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            Button("Try Again") { state.explain(request) }
                .font(.subheadline)
                .accessibilityIdentifier("\(screen)_insight_button_retry")
        }
    }

    private var header: some View {
        Label("Explanation", systemImage: "sparkles")
            .font(.headline)
            .foregroundStyle(Theme.Colors.textPrimary)
    }

    private func explanation(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.Colors.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("\(screen)_insight_label_text")
    }
}
