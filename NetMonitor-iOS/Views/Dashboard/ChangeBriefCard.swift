import NetMonitorCore
import SwiftUI

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
            ChangeSummaryView(summary: brief, ids: .init(
                keyPoints: "dashboard_list_changeBriefKeyPoints",
                text: "dashboard_label_changeBriefText",
                generated: "dashboard_label_changeBriefGenerated"
            ))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard_card_changeBrief")
    }
}
