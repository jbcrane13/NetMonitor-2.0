import SwiftUI
import NetMonitorCore

/// Reusable empty state view for lists and sections
struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    var action: EmptyStateAction?

    var body: some View {
        VStack(spacing: Theme.Layout.cardPadding) {
            // Icon
            Image(systemName: icon)
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(Theme.Colors.textTertiary)

            // Text content
            VStack(spacing: Theme.Layout.smallCornerRadius) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Optional action button
            if let action = action {
                Button {
                    action.handler()
                } label: {
                    HStack(spacing: 6) {
                        if let buttonIcon = action.icon {
                            Image(systemName: buttonIcon)
                                .font(.subheadline.weight(.semibold))
                        }
                        Text(action.title)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, Theme.Layout.sectionSpacing)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.Colors.accent.opacity(0.15))
                    )
                }
                .accessibilityIdentifier("emptyState_button_action")
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("emptyState_\(icon)")
    }
}

/// Action configuration for empty state
struct EmptyStateAction {
    let title: String
    let icon: String?
    let handler: () -> Void

    init(title: String, icon: String? = nil, handler: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.handler = handler
    }
}

// MARK: - Convenience Initializers

extension EmptyStateView {
    /// No devices found empty state
    static func noDevices(onScan: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "desktopcomputer",
            title: "No Devices Found",
            description: "No devices have been discovered on your network yet.",
            action: EmptyStateAction(title: "Scan Network", icon: "magnifyingglass", handler: onScan)
        )
    }

    /// No results empty state
    // periphery:ignore
    static func noResults(for query: String) -> EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results",
            description: "No results found for \"\(query)\". Try a different search term."
        )
    }

    /// No network empty state
    static func noNetwork(onRetry: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "wifi.slash",
            title: "No Network Connection",
            description: "Please check your network connection and try again.",
            action: EmptyStateAction(title: "Retry", icon: "arrow.clockwise", handler: onRetry)
        )
    }

    /// No recent activity empty state
    static var noActivity: EmptyStateView {
        EmptyStateView(
            icon: "clock",
            title: "No Recent Activity",
            description: "Run a network tool to see results here."
        )
    }

    /// Generic error empty state
    // periphery:ignore
    static func error(_ message: String, onRetry: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "exclamationmark.triangle",
            title: "Something Went Wrong",
            description: message,
            action: EmptyStateAction(title: "Try Again", icon: "arrow.clockwise", handler: onRetry)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 32) {
        EmptyStateView.noDevices {}
        Divider()
        EmptyStateView.noActivity
        Divider()
        EmptyStateView.noNetwork {}
    }
    .padding()
    .themedBackground()
}
