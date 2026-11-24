import NetMonitorCore
import SwiftUI

// MARK: - HeatmapAdvisorCard

/// The heatmap advisor in the Analyze sidebar (#455): the app's key points about the finished
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
                .font(.system(size: 11))
                .foregroundStyle(MacTheme.Colors.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("heatmap_label_advisorHint")
        case let .advice(keyPoints, text):
            advice(keyPoints: keyPoints, text: text)
        }
    }

    private func advice(keyPoints: [String], text: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SURVEY ADVICE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(MacTheme.Colors.labelSecondary)
                .tracking(1.4)

            // The app's judgements, word for word: the model's text can leave one out.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(keyPoints, id: \.self) { point in
                    Label(point, systemImage: "checkmark.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("heatmap_list_advisorKeyPoints")

            if let text {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.Colors.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("heatmap_label_advisorText")

                Label("Written by the on-device model from the survey's statistics", systemImage: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("heatmap_label_advisorGenerated")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macGlassCard(cornerRadius: 10, padding: 8, statusGlow: MacTheme.Colors.info)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("heatmap_card_advisor")
    }
}

#if DEBUG
#Preview {
    HeatmapAdvisorCard(phase: .advice(
        keyPoints: ["The north-east corner is weak (5% of the area, worst -84 dBm).",
                    "Try moving the access point toward the north-east corner."],
        text: HeatmapAdvisorFixture.answer
    ))
    .frame(width: 220)
    .padding()
}
#endif
