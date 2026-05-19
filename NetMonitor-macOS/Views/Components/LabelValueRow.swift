import SwiftUI

struct LabelValueRow: View {
    let label: String
    let value: String
    var labelWidth: CGFloat?
    var labelAlignment: Alignment = .leading
    var rowAlignment: VerticalAlignment = .center
    var labelFont: Font? = nil
    var valueFont: Font? = nil
    var isMonospaced = false
    var isCopyable = false
    var valueSelectionEnabled = true
    var valueColor: Color = .primary
    var valueLineLimit: Int?

    var body: some View {
        HStack(alignment: rowAlignment, spacing: 8) {
            Text(label)
                .font(labelFont)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: labelAlignment)
                .layoutPriority(1)

            if valueSelectionEnabled {
                valueText
                    .textSelection(.enabled)
            } else {
                valueText
            }

            if isCopyable {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("labelValueRow_button_copy_\(label.lowercased().replacingOccurrences(of: " ", with: "_"))")
            }

            Spacer(minLength: 8)
        }
    }

    private var valueText: some View {
        Text(value)
            .font(valueFont)
            .fontDesign(isMonospaced ? .monospaced : .default)
            .foregroundStyle(valueColor)
            .lineLimit(valueLineLimit)
            .truncationMode(.middle)
    }
}
