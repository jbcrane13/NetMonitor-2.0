import SwiftUI
import NetMonitorCore

/// A dismissable banner displayed on the dashboard when a scheduled scan detects changes.
struct ScanChangeAlertView: View {
    let diff: ScanDiff
    var onDismiss: () -> Void
    var onViewDetails: (() -> Void)? = nil

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                // Header row
                HStack(alignment: .top) {
                    Image(systemName: alertIcon)
                        .font(.title3)
                        .foregroundStyle(alertColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Network Change Detected")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(diff.scannedAt.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .accessibilityIdentifier("scanAlert_button_dismiss")
                }

                // Change counts
                HStack(spacing: Theme.Layout.itemSpacing) {
                    if !diff.newDevices.isEmpty {
                        changeChip(
                            count: diff.newDevices.count,
                            label: "New",
                            icon: "plus.circle.fill",
                            color: Theme.Colors.error
                        )
                    }

                    if !diff.removedDevices.isEmpty {
                        changeChip(
                            count: diff.removedDevices.count,
                            label: "Offline",
                            icon: "minus.circle.fill",
                            color: Theme.Colors.warning
                        )
                    }

                    if !diff.changedDevices.isEmpty {
                        changeChip(
                            count: diff.changedDevices.count,
                            label: "Changed",
                            icon: "arrow.triangle.2.circlepath",
                            color: Theme.Colors.info
                        )
                    }

                    Spacer()

                    if let onViewDetails {
                        Button("Details", action: onViewDetails)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.accent)
                            .accessibilityIdentifier("scanAlert_button_details")
                    }
                }
            }
        }
        .accessibilityIdentifier("screen_scanChangeAlert")
    }

    private func changeChip(count: Int, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text("\(count) \(label)")
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }

    private var alertIcon: String {
        diff.newDevices.isEmpty ? "exclamationmark.triangle.fill" : "shield.lefthalf.filled.badge.checkmark"
    }

    private var alertColor: Color {
        diff.newDevices.isEmpty ? Theme.Colors.warning : Theme.Colors.error
    }
}

#Preview {
    ZStack {
        Theme.Gradients.background.ignoresSafeArea()
        ScanChangeAlertView(
            diff: ScanDiff(
                newDevices: [],
                removedDevices: [],
                changedDevices: []
            ),
            onDismiss: {}
        )
        .padding()
    }
}
