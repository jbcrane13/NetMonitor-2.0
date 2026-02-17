import SwiftUI

/// A view that displays live elapsed monitoring duration
struct LiveDurationView: View {
    let startTime: Date?
    let isMonitoring: Bool

    var body: some View {
        Group {
            if isMonitoring, let start = startTime {
                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    Text(formatDuration(from: start, to: context.date))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("dashboard_duration_timer")
                }
            } else {
                Text("Not monitoring")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func formatDuration(from start: Date, to end: Date) -> String {
        let elapsed = end.timeIntervalSince(start)
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
