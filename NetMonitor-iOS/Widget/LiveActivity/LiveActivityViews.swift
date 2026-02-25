import SwiftUI
import NetMonitorCore
#if os(iOS)
import ActivityKit
import WidgetKit

// MARK: - Network Scan Live Activity Views

/// Lock screen / notification banner view for an active network scan.
struct NetworkScanLockScreenView: View {
    let context: ActivityViewContext<NetworkScanActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "network")
                    .foregroundStyle(.blue)
                    .font(.headline)
                Text(context.attributes.networkName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(context.state.devicesFound) devices")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(value: context.state.progress)
                .tint(.blue)

            Text(context.state.phase)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

/// Dynamic Island compact leading view for an active scan.
struct NetworkScanCompactLeadingView: View {
    let context: ActivityViewContext<NetworkScanActivityAttributes>

    var body: some View {
        Image(systemName: "network")
            .foregroundStyle(.blue)
            .font(.caption)
    }
}

/// Dynamic Island compact trailing view for an active scan.
struct NetworkScanCompactTrailingView: View {
    let context: ActivityViewContext<NetworkScanActivityAttributes>

    var body: some View {
        HStack(spacing: 2) {
            Text("\(context.state.devicesFound)")
                .font(.caption2)
                .monospacedDigit()
            Image(systemName: "desktopcomputer")
                .font(.caption2)
        }
        .foregroundStyle(.blue)
    }
}

/// Dynamic Island minimal view for an active scan.
struct NetworkScanMinimalView: View {
    let context: ActivityViewContext<NetworkScanActivityAttributes>

    var body: some View {
        Image(systemName: "network")
            .foregroundStyle(.blue)
            .font(.caption2)
    }
}

/// Dynamic Island expanded bottom region for an active scan.
struct NetworkScanExpandedView: View {
    let context: ActivityViewContext<NetworkScanActivityAttributes>

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Label("Scanning \(context.attributes.networkName)", systemImage: "network")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                Spacer()
                Text("\(context.state.devicesFound) found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: context.state.progress)
                .tint(.blue)
            Text(context.state.phase)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }
}

// MARK: - Speed Test Live Activity Views

/// Lock screen / notification banner view for an active speed test.
struct SpeedTestLockScreenView: View {
    let context: ActivityViewContext<SpeedTestActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "speedometer")
                    .foregroundStyle(.green)
                    .font(.headline)
                Text("Speed Test")
                    .font(.headline)
                Spacer()
                Text(context.state.phase)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: context.state.progress)
                .tint(.green)

            HStack(spacing: 20) {
                SpeedStatView(label: "Download", value: context.state.downloadSpeed > 0 ? formatSpeed(context.state.downloadSpeed) : "—")
                SpeedStatView(label: "Upload", value: context.state.uploadSpeed > 0 ? formatSpeed(context.state.uploadSpeed) : "—")
                if context.state.latency > 0 {
                    SpeedStatView(label: "Latency", value: String(format: "%.0f ms", context.state.latency))
                }
            }
        }
        .padding()
    }
}

private struct SpeedStatView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}

/// Dynamic Island compact leading view for a speed test.
struct SpeedTestCompactLeadingView: View {
    let context: ActivityViewContext<SpeedTestActivityAttributes>

    var body: some View {
        Image(systemName: "speedometer")
            .foregroundStyle(.green)
            .font(.caption)
    }
}

/// Dynamic Island compact trailing view for a speed test.
struct SpeedTestCompactTrailingView: View {
    let context: ActivityViewContext<SpeedTestActivityAttributes>

    var body: some View {
        ProgressView(value: context.state.progress)
            .progressViewStyle(.circular)
            .tint(.green)
            .frame(width: 16, height: 16)
    }
}

// MARK: - Monitoring Live Activity Views

/// Lock screen / notification banner view for ongoing network monitoring.
struct MonitoringLockScreenView: View {
    let context: ActivityViewContext<MonitoringActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: context.state.isConnected ? "wifi" : "wifi.slash")
                .font(.title2)
                .foregroundStyle(context.state.isConnected ? .green : .red)

            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.statusMessage)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    if let latency = context.state.latencyMs {
                        Label(String(format: "%.0f ms", latency), systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if context.state.alertCount > 0 {
                        Label(
                            "\(context.state.alertCount) alert\(context.state.alertCount == 1 ? "" : "s")",
                            systemImage: "bell.badge"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()
        }
        .padding()
    }
}

/// Dynamic Island compact leading for monitoring.
struct MonitoringCompactLeadingView: View {
    let context: ActivityViewContext<MonitoringActivityAttributes>

    var body: some View {
        Image(systemName: context.state.isConnected ? "wifi" : "wifi.slash")
            .foregroundStyle(context.state.isConnected ? .green : .red)
            .font(.caption)
    }
}

/// Dynamic Island compact trailing for monitoring.
struct MonitoringCompactTrailingView: View {
    let context: ActivityViewContext<MonitoringActivityAttributes>

    var body: some View {
        if let latency = context.state.latencyMs {
            Text(String(format: "%.0f ms", latency))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(context.state.isConnected ? .green : .red)
        }
    }
}

// MARK: - Live Activity Widget Configurations
// NOTE: To enable Live Activities, add these to NetmonitorWidgetBundle.body in NetmonitorWidget.swift:
//   NetmonitorNetworkScanActivity()
//   NetmonitorSpeedTestActivity()
//   NetmonitorMonitoringActivity()
//
// Also set NSSupportsLiveActivities = YES in the widget extension Info.plist
// and add the ActivityKit capability to the widget extension target in project.yml.

struct NetmonitorNetworkScanActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NetworkScanActivityAttributes.self) { context in
            NetworkScanLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.8))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    NetworkScanCompactLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    NetworkScanCompactTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    NetworkScanExpandedView(context: context)
                }
            } compactLeading: {
                NetworkScanCompactLeadingView(context: context)
            } compactTrailing: {
                NetworkScanCompactTrailingView(context: context)
            } minimal: {
                NetworkScanMinimalView(context: context)
            }
        }
    }
}

struct NetmonitorSpeedTestActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpeedTestActivityAttributes.self) { context in
            SpeedTestLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.8))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SpeedTestCompactLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SpeedTestCompactTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SpeedTestLockScreenView(context: context)
                        .padding(.bottom, 4)
                }
            } compactLeading: {
                SpeedTestCompactLeadingView(context: context)
            } compactTrailing: {
                SpeedTestCompactTrailingView(context: context)
            } minimal: {
                Image(systemName: "speedometer")
                    .foregroundStyle(.green)
                    .font(.caption2)
            }
        }
    }
}

struct NetmonitorMonitoringActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MonitoringActivityAttributes.self) { context in
            MonitoringLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.8))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MonitoringCompactLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    MonitoringCompactTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MonitoringLockScreenView(context: context)
                        .padding(.bottom, 4)
                }
            } compactLeading: {
                MonitoringCompactLeadingView(context: context)
            } compactTrailing: {
                MonitoringCompactTrailingView(context: context)
            } minimal: {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(.blue)
                    .font(.caption2)
            }
        }
    }
}
#endif
