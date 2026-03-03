import SwiftUI

/// Shared clear/trash button for tool views
struct ToolClearButton: View {
    var accessibilityID: String = "tool_button_clear"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                        .stroke(Theme.Colors.glassBorder, lineWidth: 1)
                )
        }
        .accessibilityIdentifier(accessibilityID)
    }
}
