import NetMonitorCore
import SwiftUI

/// A model-written summary under the app's key points, with the generated-text marker (#453).
/// Used by the dashboard brief and the Timeline's day summaries.
struct ChangeSummaryView: View {
    /// Accessibility identifiers, `{screen}_{element}_{descriptor}`.
    struct IDs {
        let keyPoints: String
        let text: String
        let generated: String
    }

    let summary: ChangeSummary
    let ids: IDs

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The app's judgements, word for word: the model's text can leave one out.
            if !summary.keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(summary.keyPoints, id: \.self) { point in
                        Label(point, systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(ids.keyPoints)
            }
            Text(summary.text)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(ids.text)
            Label("Written by the on-device model from the events the app recorded", systemImage: "sparkles")
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(ids.generated)
        }
    }
}
