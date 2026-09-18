import Foundation
import SwiftData
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

/// Discovery baseline gate for #279: runs `DeviceDiscoveryCoordinator.startScan()` with
/// production defaults (the real `ScanEngine.scan(pipeline: ScanPipeline.standard, ...)`
/// adapter, real `checkPort`) against whatever LAN the host machine is actually on.
///
/// Skipped by default — it needs a real network and takes real wall-clock time — and only
/// runs when `NETMONITOR_LIVE_SCAN=1` is present in the test process's environment. Because
/// `xcodebuild test` only forwards shell variables prefixed `TEST_RUNNER_` into the test
/// process, the node invokes this with `TEST_RUNNER_NETMONITOR_LIVE_SCAN=1`.
///
/// The orchestrator greps the test log for the exact `LIVE_SCAN devices=<n> gateway=<found|missing>`
/// line this test prints and compares it against a baseline captured from `main` — a skipped
/// test (the line absent) is treated as a failed gate.
@Suite(.serialized)
@MainActor
struct DeviceDiscoveryCoordinatorLiveScanTests {

    @Test func liveScanFindsGatewayAndReportsDeviceCount() async throws {
        guard ProcessInfo.processInfo.environment["NETMONITOR_LIVE_SCAN"] == "1" else {
            print("LIVE_SCAN skipped")
            #expect(Bool(true))
            return
        }

        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])

        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: container.mainContext,
            arpScanner: ARPScannerService(),
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager()
        )

        coordinator.startScan()

        let deadline = ContinuousClock.now + .seconds(90)
        while coordinator.isScanning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        if coordinator.isScanning {
            coordinator.stopScan()
        }

        // Accept every gateway candidate we can derive rather than preferring one and only
        // falling back to another when it's nil, so a mismatch between them doesn't
        // spuriously read as "missing":
        //   - the active NetworkProfile's own gatewayIP, if one was detected;
        //   - the sysctl routing-table gateway for the SAME interface the coordinator
        //     would fall back to when no profile is active (not always en0 — #279);
        //   - the plain en0-default detection, as a last resort.
        var gatewayCandidates: Set<String> = []
        if let profileGateway = coordinator.networkProfile?.gatewayIP {
            gatewayCandidates.insert(profileGateway)
        }
        let fallbackInterface = coordinator.networkProfile?.interfaceName
            ?? DeviceDiscoveryCoordinator.selectFallbackInterface()
        if let fallbackInterface, let detectedGateway = NetworkUtilities.detectDefaultGateway(interface: fallbackInterface) {
            gatewayCandidates.insert(detectedGateway)
        }
        if let detectedGatewayDefault = NetworkUtilities.detectDefaultGateway() {
            gatewayCandidates.insert(detectedGatewayDefault)
        }
        let gatewayFound = coordinator.discoveredDevices.contains { gatewayCandidates.contains($0.ipAddress) }

        print("LIVE_SCAN devices=\(coordinator.discoveredDevices.count) gateway=\(gatewayFound ? "found" : "missing")")

        #expect(Bool(true))
    }
}
