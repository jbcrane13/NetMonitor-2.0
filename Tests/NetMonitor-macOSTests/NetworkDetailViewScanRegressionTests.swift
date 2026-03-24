import Foundation
import SwiftData
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

// Regression tests for commit 510c0c8:
// "Scan This Network" button was silently no-op because the scanAction closure
// captured stale struct copies via value-type semantics. Fixed by replacing
// the closure pattern with direct @Environment(DeviceDiscoveryCoordinator.self).
//
// These tests prove the coordinator behaviour the UI button now calls directly:
// scanNetwork(_:) must trigger a scan, set isScanning=true, and be idempotent
// when already scanning. If scanNetwork() ever silently regresses, these fail.

@Suite("NetworkDetailView Scan Regression", .serialized)
@MainActor
struct NetworkDetailViewScanRegressionTests {

    // MARK: - Helpers

    private func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }

    private func makeCoordinator(context: ModelContext) -> DeviceDiscoveryCoordinator {
        DeviceDiscoveryCoordinator(
            modelContext: context,
            arpScanner: ARPScannerService(timeout: 0.05),
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager()
        )
    }

    private func makeNetwork() -> NetworkUtilities.IPv4Network {
        // 192.168.1.0/24
        NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A80100,
            broadcastAddress: 0xC0A801FF,
            interfaceAddress: 0xC0A80101,
            netmask: 0xFFFFFF00
        )
    }

    private func makeProfile(name: String = "TestNet") -> NetworkProfile {
        NetworkProfile(
            id: UUID(),
            interfaceName: "en0",
            ipAddress: "192.168.1.10",
            network: makeNetwork(),
            connectionType: .wifi,
            name: name,
            gatewayIP: "192.168.1.1",
            subnet: "192.168.1.0/24",
            isLocal: true,
            discoveryMethod: .auto
        )
    }

    // MARK: - Regression: scanNetwork() must trigger a real scan

    @Test("scanNetwork sets networkProfile to the passed profile")
    func scanNetworkSetsNetworkProfile() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)
        let profile = makeProfile(name: "HomeNet")

        coordinator.scanNetwork(profile)

        #expect(coordinator.networkProfile?.id == profile.id,
                "networkProfile must be updated — previously the stale closure never propagated the profile to the coordinator")
    }

    @Test("scanNetwork triggers isScanning=true")
    func scanNetworkTriggersIsScanning() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        #expect(coordinator.isScanning == false)
        coordinator.scanNetwork(makeProfile())
        #expect(coordinator.isScanning == true,
                "scanNetwork must set isScanning=true — if this fails the scan button is silently broken again")
    }

    @Test("scanNetwork while already scanning is idempotent")
    func scanNetworkWhileAlreadyScanningIsIdempotent() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        coordinator.scanNetwork(makeProfile(name: "Net1"))
        #expect(coordinator.isScanning == true)
        let progressAfterFirst = coordinator.scanProgress

        // A second call while scanning must not restart (guard !isScanning in startScan)
        coordinator.scanNetwork(makeProfile(name: "Net2"))
        #expect(coordinator.isScanning == true)
        #expect(coordinator.scanProgress == progressAfterFirst,
                "scanProgress must not reset when scanNetwork is called while already scanning")
    }

    @Test("stopScan clears isScanning so button re-enables")
    func stopScanClearsIsScanning() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        coordinator.scanNetwork(makeProfile())
        #expect(coordinator.isScanning == true)

        coordinator.stopScan()
        #expect(coordinator.isScanning == false,
                "stopScan must clear isScanning — UI button .disabled state depends on this")
    }

    @Test("scanProgress advances once scan task begins")
    func scanProgressAdvancesWhenScanBegins() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        #expect(coordinator.scanProgress == 0.0)
        coordinator.scanNetwork(makeProfile())
        #expect(coordinator.isScanning == true)

        // Give scan task time to advance past the 0.1 progress checkpoint
        try await Task.sleep(for: .milliseconds(300))
        #expect(coordinator.scanProgress > 0.0,
                "scanProgress must advance — the UI ProgressView depends on this value")

        coordinator.stopScan()
    }
}
