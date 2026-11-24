import NetMonitorCore
import SwiftUI

// MARK: - HeatmapAdvisorCard

/// The heatmap advisor on the survey result (#455): the app's key points about the finished
/// survey word for word, then the on-device model's wording of them with the generated marker.
/// Without the model the key points still show; a sparse survey shows the app's hint.
struct HeatmapAdvisorCard: View {
    let phase: HeatmapAdvisorState.Phase

    var body: some View {
        switch phase {
        case .hidden:
            EmptyView()
        case let .sparse(hint):
            Label(hint, systemImage: "mappin.and.ellipse")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("heatmap_label_advisorHint")
        case let .advice(keyPoints, text):
            advice(keyPoints: keyPoints, text: text)
        }
    }

    private func advice(keyPoints: [String], text: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // On iOS 26 a container's identifier doesn't reach XCUITest, so the card's is on its title.
            Text("SURVEY ADVICE")
                .font(.system(.caption2, weight: .heavy))
                .foregroundStyle(Theme.Colors.textTertiary)
                .tracking(2.0)
                .accessibilityIdentifier("heatmap_card_advisor")
            // The app's judgements, word for word: the model's text can leave one out.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(keyPoints, id: \.self) { point in
                    Label(point, systemImage: "checkmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("heatmap_list_advisorKeyPoints")
            if let text {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("heatmap_label_advisorText")
                Label("Written by the on-device model from the survey's statistics", systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("heatmap_label_advisorGenerated")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
