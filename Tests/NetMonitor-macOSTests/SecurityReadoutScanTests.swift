import Foundation
import SwiftData
import Testing
import NetMonitorCore
import NetworkScanKit
@testable import NetMonitor_macOS

// MARK: - #454: a probed open port becomes a security finding

@Suite("Security readout from a scan (#454)", .serialized)
@MainActor
struct SecurityReadoutScanTests {
    /// The quick scan probes a security-rule port (telnet), the coordinator saves it to
    /// `openPorts`, and the readout's rule table turns the saved row into a finding.
    @Test func aProbedTelnetPortBecomesASecurityFinding() async throws {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(),
            pipelineFactory: { _ in
                ScanPipeline(steps: [
                    ScanPipeline.Step(phases: [CameraPhase()], concurrent: false),
                    ScanPipeline.Step(phases: [QuickPortScanPhase(checker: { _, port, _ in port == 23 })], concurrent: false)
                ])
            },
            portChecker: { _, _, _ in false },
            scanHistory: .forTesting(),
            dispatcher: DeviceEventDispatcher(),
            joinClock: .forTests
        )

        coordinator.startScan()
        let deadline = ContinuousClock.now + .seconds(15)
        while coordinator.isScanning || coordinator.lastScanTime == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        let device = try #require(try context.fetch(FetchDescriptor<LocalDevice>()).first { $0.ipAddress == CameraPhase.ip })
        #expect(device.openPorts == [23])
        #expect(SecurityRuleTable.findings(for: [device]).map(\.title) == ["Telnet port 23 is open"])
    }
}

/// Finds one device, as the ARP phase would.
private struct CameraPhase: ScanPhase, Sendable {
    static let ip = "192.0.2.23"
    let id: ScanPhaseID = "securityFixture"
    let displayName = "Security fixture"
    let weight: Double = 1.0

    func execute(context: ScanContext, accumulator: ScanAccumulator, onProgress: @Sendable (Double) async -> Void) async {
        await accumulator.upsert(DiscoveredDevice(
            ipAddress: Self.ip, hostname: "camera.local", vendor: nil, macAddress: "AA:BB:CC:DD:EE:23",
            latency: 3, discoveredAt: Date(), source: .local
        ))
        await onProgress(1.0)
    }
}
