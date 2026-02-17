import SwiftUI
import NetMonitorCore

/// A styled run/stop button for network tools
struct ToolRunButton: View {
    let title: String
    let icon: String
    let isRunning: Bool
    var stopTitle: String = "Stop"
    var stopIcon: String = "stop.fill"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isRunning {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.textPrimary))
                        .scaleEffect(0.8)

                    Image(systemName: stopIcon)
                        .font(.body.weight(.semibold))
                } else {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                }

                Text(isRunning ? stopTitle : title)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                        .fill(isRunning ? Theme.Colors.error.opacity(0.3) : Theme.Colors.accent.opacity(0.3))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                    .stroke(isRunning ? Theme.Colors.error.opacity(0.5) : Theme.Colors.accent.opacity(0.5), lineWidth: 1)
            )
            .shadow(
                color: isRunning ? Theme.Colors.error.opacity(0.3) : Theme.Colors.accent.opacity(0.3),
                radius: 8,
                y: 3
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("toolRun_button_\(isRunning ? "stop" : "start")")
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Theme.Gradients.background
            .ignoresSafeArea()

        VStack(spacing: 16) {
            ToolRunButton(
                title: "Start Ping",
                icon: "play.fill",
                isRunning: false,
                action: {}
            )

            ToolRunButton(
                title: "Start Ping",
                icon: "play.fill",
                isRunning: true,
                stopTitle: "Stop Ping",
                action: {}
            )

            ToolRunButton(
                title: "Run Traceroute",
                icon: "arrow.right",
                isRunning: false,
                action: {}
            )
        }
        .padding()
    }
}
