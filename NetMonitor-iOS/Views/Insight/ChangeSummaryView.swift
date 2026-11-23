import NetMonitorCore
import SwiftUI

/// A model-written summary under the app's key points, with the generated-text marker (#453).
/// Used by the dashboard brief and the Timeline's day summaries.
struct ChangeSummaryView: View {
    let summary: ChangeSummary
    /// Accessibility prefix, such as "dashboard_changeBrief".
    let idPrefix: String

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
                .accessibilityIdentifier("\(idPrefix)_list_keyPoints")
            }
            Text(summary.text)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("\(idPrefix)_label_text")
            Label("Written by the on-device model from the events the app recorded", systemImage: "sparkles")
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("\(idPrefix)_label_generated")
        }
    }
}

/// The dashboard's "since yesterday" brief (#453). Shows only a finished brief; the
/// dashboard hides it otherwise, never showing it blank.
struct ChangeBriefCard: View {
    let brief: ChangeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SINCE YESTERDAY")
                .font(.system(.caption2, weight: .heavy))
                .foregroundStyle(Theme.Colors.textTertiary)
                .tracking(2.0)
            ChangeSummaryView(summary: brief, idPrefix: "dashboard_changeBrief")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard_card_changeBrief")
    }
}
