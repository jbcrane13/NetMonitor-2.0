import NetMonitorCore
import SwiftUI

/// The dashboard's "since yesterday" brief (#491 S6): the app's key points word for word, the
/// on-device model's paragraph and the generated-text marker. Shown only with a finished brief;
/// the dashboard leaves it out otherwise, never showing it blank.
struct ChangeBriefCard: View {
    let brief: ChangeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(MacTheme.Colors.info).frame(width: 5, height: 5)
                Text("SINCE YESTERDAY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                    .tracking(1.4)
                Spacer()
            }

            // The app's judgements, word for word: the model's text can leave one out.
            if !brief.keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(brief.keyPoints, id: \.self) { point in
                        Label(point, systemImage: "checkmark.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MacTheme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("networkDetail_list_changeBriefKeyPoints")
            }

            Text(brief.text)
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.Colors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("networkDetail_label_changeBriefText")

            Label("Written by the on-device model from the events the app recorded", systemImage: "sparkles")
                .font(.system(size: 10))
                .foregroundStyle(MacTheme.Colors.labelSecondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("networkDetail_label_changeBriefGenerated")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macGlassCard(cornerRadius: 14, padding: 10, statusGlow: MacTheme.Colors.info)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("networkDetail_card_changeBrief")
    }
}

#if DEBUG
#Preview {
    ChangeBriefCard(brief: ChangeSummary(
        keyPoints: ["1 device joined the network.", "The gateway changed."],
        text: "A printer joined the network and the gateway changed since yesterday."
    ))
    .frame(width: 380)
    .padding()
}
#endif
