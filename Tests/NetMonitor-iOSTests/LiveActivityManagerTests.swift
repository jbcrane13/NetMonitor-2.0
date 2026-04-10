import Testing
import Foundation
@testable import NetMonitor_iOS

// MARK: - LiveActivityManager Tests
//
// ActivityKit is not available in the iOS Simulator test environment, so these
// tests verify the manager's state-tracking logic rather than actual activity
// creation (which would silently no-op when activities are unavailable).

#if os(iOS)

@MainActor
struct LiveActivityManagerTests {

    @Test("shared instance is accessible")
    func sharedInstanceExists() {
        let manager = LiveActivityManager.shared
        _ = manager
        #expect(Bool(true))
    }

    @Test("hasScanActivity is false initially")
    func hasScanActivityInitiallyFalse() {
        let manager = LiveActivityManager.shared
        // On simulator, activities are not started, so this should remain false
        #expect(manager.hasScanActivity == false)
    }

    @Test("hasSpeedTestActivity is false initially")
    func hasSpeedTestActivityInitiallyFalse() {
        let manager = LiveActivityManager.shared
        #expect(manager.hasSpeedTestActivity == false)
    }

    @Test("hasMonitoringActivity is false initially")
    func hasMonitoringActivityInitiallyFalse() {
        let manager = LiveActivityManager.shared
        #expect(manager.hasMonitoringActivity == false)
    }

    @Test("startScanActivity does not crash when activities unavailable")
    func startScanActivityNoCrash() {
        let manager = LiveActivityManager.shared
        // On simulator, ActivityAuthorizationInfo().areActivitiesEnabled is false
        // so start* methods should silently return
        manager.startScanActivity(networkName: "TestNet", subnet: "192.168.1.0/24")
        #expect(Bool(true))
    }

    @Test("startSpeedTestActivity does not crash when activities unavailable")
    func startSpeedTestActivityNoCrash() {
        let manager = LiveActivityManager.shared
        manager.startSpeedTestActivity()
        #expect(Bool(true))
    }

    @Test("startMonitoringActivity does not crash when activities unavailable")
    func startMonitoringActivityNoCrash() {
        let manager = LiveActivityManager.shared
        manager.startMonitoringActivity(networkName: "HomeNet")
        #expect(Bool(true))
    }

    @Test("endScanActivity does not crash when no activity running")
    func endScanActivityNoCrash() async {
        let manager = LiveActivityManager.shared
        await manager.endScanActivity(devicesFound: 5)
        #expect(Bool(true))
    }

    @Test("endSpeedTestActivity does not crash when no activity running")
    func endSpeedTestActivityNoCrash() async {
        let manager = LiveActivityManager.shared
        await manager.endSpeedTestActivity(downloadSpeed: 100, uploadSpeed: 50, latency: 20)
        #expect(Bool(true))
    }

    @Test("endMonitoringActivity does not crash when no activity running")
    func endMonitoringActivityNoCrash() async {
        let manager = LiveActivityManager.shared
        await manager.endMonitoringActivity()
        #expect(Bool(true))
    }
}

// MARK: - NetworkScanActivityAttributes Tests

struct NetworkScanActivityAttributesTests {

    @Test("content state stores progress")
    func contentStateProgress() {
        let state = NetworkScanActivityAttributes.ContentState(
            progress: 0.5,
            devicesFound: 3,
            phase: "Scanning…"
        )
        #expect(state.progress == 0.5)
        #expect(state.devicesFound == 3)
        #expect(state.phase == "Scanning…")
    }

    @Test("attributes store network name and subnet")
    func attributesStore() {
        let attrs = NetworkScanActivityAttributes(networkName: "Home", subnet: "192.168.1.0/24")
        #expect(attrs.networkName == "Home")
        #expect(attrs.subnet == "192.168.1.0/24")
    }

    @Test("subnet is optional")
    func subnetIsOptional() {
        let attrs = NetworkScanActivityAttributes(networkName: "Home", subnet: nil)
        #expect(attrs.subnet == nil)
    }
}

// MARK: - SpeedTestActivityAttributes Tests

struct SpeedTestActivityAttributesTests {

    @Test("content state stores speeds and phase")
    func contentStateStoresSpeeds() {
        let state = SpeedTestActivityAttributes.ContentState(
            downloadSpeed: 150.5,
            uploadSpeed: 50.2,
            latency: 12.0,
            phase: "Testing download…",
            progress: 0.4
        )
        #expect(state.downloadSpeed == 150.5)
        #expect(state.uploadSpeed == 50.2)
        #expect(state.latency == 12.0)
        #expect(state.phase == "Testing download…")
        #expect(state.progress == 0.4)
    }
}

// MARK: - MonitoringActivityAttributes Tests

struct MonitoringActivityAttributesTests {

    @Test("content state stores connection info")
    func contentStateStoresConnectionInfo() {
        let state = MonitoringActivityAttributes.ContentState(
            isConnected: true,
            latencyMs: 8.5,
            alertCount: 2,
            statusMessage: "Connected · Wi-Fi",
            connectionType: "Wi-Fi"
        )
        #expect(state.isConnected == true)
        #expect(state.latencyMs == 8.5)
        #expect(state.alertCount == 2)
        #expect(state.statusMessage == "Connected · Wi-Fi")
    }

    @Test("latencyMs is optional")
    func latencyIsOptional() {
        let state = MonitoringActivityAttributes.ContentState(
            isConnected: false,
            latencyMs: nil,
            alertCount: 0,
            statusMessage: "Offline",
            connectionType: "None"
        )
        #expect(state.latencyMs == nil)
    }

    @Test("attributes store start time")
    func attributesStoreStartTime() {
        let now = Date()
        let attrs = MonitoringActivityAttributes(startTime: now, networkName: "Work")
        #expect(attrs.startTime == now)
        #expect(attrs.networkName == "Work")
    }
}

#endif
