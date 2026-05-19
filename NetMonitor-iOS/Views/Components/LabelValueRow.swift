import SwiftUI

struct LabelValueRow: View {
    let label: String
    let value: String
    var font: Font? = nil
    var isMonospaced = false
    var valueSelectionEnabled = true
    var labelColor: Color = Theme.Colors.textSecondary
    var valueColor: Color = Theme.Colors.textPrimary

    var body: some View {
        HStack {
            Text(label)
                .font(font)
                .foregroundStyle(labelColor)

            Spacer()

            if valueSelectionEnabled {
                valueText
                    .textSelection(.enabled)
            } else {
                valueText
            }
        }
    }

    private var valueText: some View {
        Text(value)
            .font(font)
            .fontDesign(isMonospaced ? .monospaced : .default)
            .foregroundStyle(valueColor)
    }
}
