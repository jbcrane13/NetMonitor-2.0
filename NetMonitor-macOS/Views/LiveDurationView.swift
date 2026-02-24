import SwiftUI
import NetMonitorCore

/// A view that displays live elapsed monitoring duration
struct LiveDurationView: View {
    let startTime: Date?
    let isMonitoring: Bool

    var body: some View {
        Group {
            if isMonitoring, let start = startTime {
                _DurationTickView(startTime: start)
            } else {
                Text("Not monitoring")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Inner view that ticks every second using a task loop.
private struct _DurationTickView: View {
    let startTime: Date
    @State private var elapsed: TimeInterval = 0

    var body: some View {
        Text(formatDuration(elapsed))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("dashboard_duration_timer")
            .task {
                elapsed = Date().timeIntervalSince(startTime)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    elapsed = Date().timeIntervalSince(startTime)
                }
            }
    }

    private func formatDuration(_ elapsed: TimeInterval) -> String {
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

#Preview("Monitoring Active") {
    LiveDurationView(
        startTime: Date().addingTimeInterval(-3723), // 1 hour, 2 min, 3 sec ago
        isMonitoring: true
    )
    .padding()
}

#Preview("Not Monitoring") {
    LiveDurationView(
        startTime: nil,
        isMonitoring: false
    )
    .padding()
}
