import SwiftUI
import NetMonitorCore

// MARK: - Presence (#583)

extension Theme.Colors {
    /// Online green, offline red-grey; not checked recently has its own neutral style (a dashed dot).
    static func presence(_ freshness: PresenceFreshness) -> Color {
        switch freshness {
        case .online: success
        case .notCheckedRecently: textTertiary
        case .offline: error.opacity(0.8)
        }
    }
}

/// A row's presence as a dot: filled for online and offline, dashed for not checked recently, so
/// the states never differ by colour alone. Hidden from VoiceOver; the text beside it says it.
struct PresenceDot: View {
    let freshness: PresenceFreshness
    var size: CGFloat = Theme.Layout.presenceDotSize
    var accessibilityID: String?

    var body: some View {
        Group {
            if freshness == .notCheckedRecently {
                Image(systemName: "circle.dashed")
                    .resizable()
                    .fontWeight(.bold)
            } else {
                Circle()
                    .fill(Theme.Colors.presence(freshness))
            }
        }
        .foregroundStyle(Theme.Colors.presence(freshness))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .accessibilityIdentifier(accessibilityID ?? "")
    }
}

/// The dot and "Online · Last seen 5 min ago".
struct PresenceLine: View {
    let freshness: PresenceFreshness
    let text: String
    var accessibilityID: String?

    var body: some View {
        HStack(spacing: Theme.Layout.inlineSpacing) {
            PresenceDot(freshness: freshness)
            Text(text)
                .font(.caption2)
                .foregroundStyle(freshness == .online ? Theme.Colors.success : Theme.Colors.textSecondary)
                .lineLimit(1)
        }
        .accessibilityIdentifier(accessibilityID ?? "")
    }
}
