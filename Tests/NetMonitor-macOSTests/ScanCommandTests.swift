import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_macOS

/// A phase that holds the scan open until it's cancelled.
private struct HoldScanPhase: ScanPhase, Sendable {
    let id: ScanPhaseID = "scanCommandHold"
    let displayName = "Hold"
    let weight: Double = 1.0
    func execute(context: ScanContext, accumulator: ScanAccumulator, onProgress: @Sendable (Double) async -> Void) async {
        try? await Task.sleep(for: .seconds(30))
    }
}

/// #444: File ▸ Scan Network and ⌘R scan the network dashboard on screen.
@MainActor
struct ScanCommandTests {
    @Test("The command scans the selected dashboard's network, not the last one scanned")
    func scansTheSelectedNetwork() throws {
        let suite = "ScanCommandTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: { [] })
        let office = try #require(manager.addProfile(gateway: "10.20.0.1", subnet: "10.20.0.0/24", name: "Office"))
        let home = try #require(manager.addProfile(gateway: "10.30.0.1", subnet: "10.30.0.0/24", name: "Home"))
        let schema = Schema([LocalDevice.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: container.mainContext,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: manager,
            pipelineFactory: { _ in ScanPipeline(steps: [ScanPipeline.Step(phases: [HoldScanPhase()], concurrent: false)]) },
            scanHistory: .forTesting(),
            dispatcher: DeviceEventDispatcher(),
            joinClock: .forTests
        )
        defer { coordinator.stopScan() }

        coordinator.scanNetwork(office)
        coordinator.stopScan()

        ContentView.scan(with: coordinator, selected: home)
        #expect(coordinator.isScanning)
        #expect(coordinator.networkProfile?.id == home.id)
    }
}
