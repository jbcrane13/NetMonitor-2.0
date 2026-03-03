import Foundation
#if os(iOS)
@preconcurrency import ActivityKit

// MARK: - ActivityAttributes (shared with Widget target)

struct NetworkScanActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progress: Double
        var devicesFound: Int
        var phase: String
    }

    var networkName: String
    var subnet: String?
}

struct SpeedTestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var downloadSpeed: Double
        var uploadSpeed: Double
        var latency: Double
        var phase: String
        var progress: Double
    }
}

struct MonitoringActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isConnected: Bool
        var latencyMs: Double?
        var alertCount: Int
        var statusMessage: String
        var connectionType: String
    }

    var startTime: Date
    var networkName: String?
}

/// Manages the lifecycle of Live Activities for network scans, speed tests, and monitoring.
///
/// Call `start*Activity()` when an operation begins, `update*Activity()` during progress,
/// and `end*Activity()` when the operation completes. Activities are silently skipped
/// on devices that don't support Live Activities (e.g. older hardware, simulator).
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var scanActivity: Activity<NetworkScanActivityAttributes>?
    private var speedTestActivity: Activity<SpeedTestActivityAttributes>?
    private var monitoringActivity: Activity<MonitoringActivityAttributes>?

    private var activitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private init() {}

    // MARK: - Network Scan

    func startScanActivity(networkName: String, subnet: String? = nil) {
        guard activitiesEnabled else { return }

        let attributes = NetworkScanActivityAttributes(networkName: networkName, subnet: subnet)
        let initialState = NetworkScanActivityAttributes.ContentState(
            progress: 0,
            devicesFound: 0,
            phase: "Starting scan…"
        )
        let content = ActivityContent(
            state: initialState,
            staleDate: .now.addingTimeInterval(300)
        )

        do {
            scanActivity = try Activity.request(attributes: attributes, content: content)
        } catch {
            // Live Activities not available or user has disabled them
        }
    }

    // periphery:ignore
    func updateScanActivity(progress: Double, devicesFound: Int, phase: String) async {
        guard let activity = scanActivity else { return }
        let state = NetworkScanActivityAttributes.ContentState(
            progress: progress,
            devicesFound: devicesFound,
            phase: phase
        )
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(300))
        await activity.update(content)
    }

    func endScanActivity(devicesFound: Int) async {
        guard let activity = scanActivity else { return }
        let finalState = NetworkScanActivityAttributes.ContentState(
            progress: 1.0,
            devicesFound: devicesFound,
            phase: devicesFound == 1 ? "Found 1 device" : "Found \(devicesFound) devices"
        )
        let content = ActivityContent(state: finalState, staleDate: nil)
        await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(8)))
        scanActivity = nil
    }

    // MARK: - Speed Test

    func startSpeedTestActivity() {
        guard activitiesEnabled else { return }

        let attributes = SpeedTestActivityAttributes()
        let initialState = SpeedTestActivityAttributes.ContentState(
            downloadSpeed: 0,
            uploadSpeed: 0,
            latency: 0,
            phase: "Measuring latency…",
            progress: 0
        )
        let content = ActivityContent(
            state: initialState,
            staleDate: .now.addingTimeInterval(120)
        )

        do {
            speedTestActivity = try Activity.request(attributes: attributes, content: content)
        } catch {
            // Live Activities not available
        }
    }

    // periphery:ignore
    func updateSpeedTestActivity(
        downloadSpeed: Double,
        uploadSpeed: Double,
        latency: Double,
        phase: String,
        progress: Double
    ) async {
        guard let activity = speedTestActivity else { return }
        let state = SpeedTestActivityAttributes.ContentState(
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
            latency: latency,
            phase: phase,
            progress: progress
        )
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(120))
        await activity.update(content)
    }

    func endSpeedTestActivity(downloadSpeed: Double, uploadSpeed: Double, latency: Double) async {
        guard let activity = speedTestActivity else { return }
        let finalState = SpeedTestActivityAttributes.ContentState(
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
            latency: latency,
            phase: "Complete",
            progress: 1.0
        )
        let content = ActivityContent(state: finalState, staleDate: nil)
        await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(10)))
        speedTestActivity = nil
    }

    // MARK: - Network Monitoring

    func startMonitoringActivity(networkName: String? = nil) {
        guard activitiesEnabled else { return }

        let attributes = MonitoringActivityAttributes(startTime: .now, networkName: networkName)
        let initialState = MonitoringActivityAttributes.ContentState(
            isConnected: true,
            latencyMs: nil,
            alertCount: 0,
            statusMessage: "Monitoring network…",
            connectionType: "Wi-Fi"
        )
        let content = ActivityContent(
            state: initialState,
            staleDate: .now.addingTimeInterval(3600)
        )

        do {
            monitoringActivity = try Activity.request(attributes: attributes, content: content)
        } catch {
            // Live Activities not available
        }
    }

    // periphery:ignore
    func updateMonitoringActivity(
        isConnected: Bool,
        latencyMs: Double?,
        alertCount: Int,
        statusMessage: String,
        connectionType: String
    ) async {
        guard let activity = monitoringActivity else { return }
        let state = MonitoringActivityAttributes.ContentState(
            isConnected: isConnected,
            latencyMs: latencyMs,
            alertCount: alertCount,
            statusMessage: statusMessage,
            connectionType: connectionType
        )
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(3600))
        await activity.update(content)
    }

    func endMonitoringActivity() async {
        guard let activity = monitoringActivity else { return }
        let finalState = MonitoringActivityAttributes.ContentState(
            isConnected: false,
            latencyMs: nil,
            alertCount: 0,
            statusMessage: "Monitoring stopped",
            connectionType: "—"
        )
        let content = ActivityContent(state: finalState, staleDate: nil)
        await activity.end(content, dismissalPolicy: .immediate)
        monitoringActivity = nil
    }

    // MARK: - State Queries

    var hasScanActivity: Bool { scanActivity != nil }
    var hasSpeedTestActivity: Bool { speedTestActivity != nil }
    var hasMonitoringActivity: Bool { monitoringActivity != nil }
}
#endif
