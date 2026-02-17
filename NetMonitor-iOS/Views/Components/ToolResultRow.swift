import SwiftUI
import NetMonitorCore

/// A unified row displaying a label-value pair
/// Used for both tool results and metric displays
struct ToolResultRow: View {
    let label: String
    let value: String
    var icon: String? = nil
    var valueColor: Color = Theme.Colors.textPrimary
    var isMonospaced: Bool = false
    var selectable: Bool = false

    var body: some View {
        HStack {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: Theme.Layout.smallIconSize))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 20)
            }

            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)

            Spacer()

            Group {
                if selectable {
                    Text(value)
                        .font(isMonospaced ? .system(.subheadline, design: .monospaced) : .subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(valueColor)
                        .textSelection(.enabled)
                } else {
                    Text(value)
                        .font(isMonospaced ? .system(.subheadline, design: .monospaced) : .subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(valueColor)
                }
            }
        }
        .accessibilityIdentifier("toolResult_row_\(label.lowercased().replacingOccurrences(of: " ", with: "_"))")
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Theme.Gradients.background
            .ignoresSafeArea()

        GlassCard {
            VStack(spacing: 12) {
                ToolResultRow(
                    label: "IP Address",
                    value: "192.168.1.1",
                    icon: "network",
                    isMonospaced: true,
                    selectable: true
                )

                Divider().background(Theme.Colors.glassBorder)

                ToolResultRow(
                    label: "Response Time",
                    value: "45 ms",
                    icon: "clock",
                    selectable: true
                )

                Divider().background(Theme.Colors.glassBorder)

                ToolResultRow(
                    label: "Status",
                    value: "Success",
                    icon: "checkmark.circle",
                    valueColor: Theme.Colors.success,
                    selectable: true
                )

                Divider().background(Theme.Colors.glassBorder)

                ToolResultRow(
                    label: "Error",
                    value: "Connection timeout",
                    icon: "xmark.circle",
                    valueColor: Theme.Colors.error,
                    selectable: true
                )
            }
        }
        .padding()
    }
}
