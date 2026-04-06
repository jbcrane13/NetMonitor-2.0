import SwiftUI
import NetMonitorCore

// MARK: - Status Badge
/// A pill-shaped badge showing connection/device status
struct StatusBadge: View {
    let status: StatusType
    var showLabel: Bool = true
    var size: BadgeSize = .medium

    enum BadgeSize {
        case small, medium, large

        var fontSize: Font {
            switch self {
            case .small: .caption2
            case .medium: .caption
            case .large: .subheadline
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .small: 8
            case .medium: 10
            case .large: 14
            }
        }

        var padding: EdgeInsets {
            switch self {
            case .small: EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6)
            case .medium: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            case .large: EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            }
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: size.iconSize, height: size.iconSize)
                .shadow(color: status.color.opacity(0.5), radius: 4)

            if showLabel {
                Text(status.label)
                    .font(size.fontSize)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
        .padding(size.padding)
        .background(
            Capsule()
                .fill(status.color.opacity(0.2))
        )
        .overlay(
            Capsule()
                .stroke(status.color.opacity(0.3), lineWidth: 1)
        )
        .accessibilityIdentifier("statusBadge_label_\(status.rawValue)")
        .accessibilityLabel("\(status.label) status")
    }
}

// MARK: - Status Dot
/// A simple status indicator dot without label
struct StatusDot: View {
    let status: StatusType
    var size: CGFloat = 10
    var animated: Bool = false

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .shadow(color: status.color.opacity(0.5), radius: animated && isPulsing ? 8 : 4)
            .scaleEffect(animated && isPulsing ? 1.2 : 1.0)
            .onAppear {
                if animated && status == .online {
                    withAnimation(Theme.Animation.pulse) {
                        isPulsing = true
                    }
                }
            }
            .accessibilityIdentifier("statusDot_image_\(status.rawValue)")
            .accessibilityLabel("\(status.label)")
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Theme.Gradients.background
            .ignoresSafeArea()

        VStack(spacing: 20) {
            Text("Status Badges")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            HStack(spacing: 12) {
                StatusBadge(status: .online)
                StatusBadge(status: .offline)
                StatusBadge(status: .idle)
            }

            Text("Sizes")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            HStack(spacing: 12) {
                StatusBadge(status: .online, size: .small)
                StatusBadge(status: .online, size: .medium)
                StatusBadge(status: .online, size: .large)
            }

            Text("Status Dots")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            HStack(spacing: 20) {
                StatusDot(status: .online, animated: true)
                StatusDot(status: .offline)
                StatusDot(status: .idle)
                StatusDot(status: .unknown)
            }
        }
        .padding()
    }
}
