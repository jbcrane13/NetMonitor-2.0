import SwiftUI
import UIKit

/// A collapsible card showing a raw text/JSON server response with a
/// copy-to-clipboard button. Used by tool views (e.g. WHOIS) that want to
/// surface the full raw response alongside a parsed summary.
struct RawResponseCard: View {
    let title: String
    let rawText: String
    @Binding var isExpanded: Bool
    var sectionAccessibilityID: String
    var disclosureAccessibilityID: String
    var copyButtonAccessibilityID: String

    var body: some View {
        GlassCard {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(rawText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        UIPasteboard.general.string = rawText
                    } label: {
                        Label("Copy \(title)", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .accessibilityIdentifier(copyButtonAccessibilityID)
                }
                .padding(.top, 8)
            } label: {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .accessibilityIdentifier(disclosureAccessibilityID)
        }
        .accessibilityIdentifier(sectionAccessibilityID)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Theme.Gradients.background
            .ignoresSafeArea()

        RawResponseCard(
            title: "Raw Response",
            rawText: "{\n  \"objectClassName\": \"domain\"\n}",
            isExpanded: .constant(true),
            sectionAccessibilityID: "preview_section_raw",
            disclosureAccessibilityID: "preview_disclosure_raw",
            copyButtonAccessibilityID: "preview_button_copyRaw"
        )
        .padding()
    }
}
