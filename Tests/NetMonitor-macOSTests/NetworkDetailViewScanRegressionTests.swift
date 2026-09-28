import Foundation
import SwiftData
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS
import NetworkScanKit

// Regression tests for commit 510c0c8:
// "Scan This Network" button was silently no-op because the scanAction closure
// captured stale struct copies via value-type semantics. Fixed by replacing
// the closure pattern with direct @Environment(DeviceDiscoveryCoordinator.self).
//
// These tests prove the coordinator behaviour the UI button now calls directly:
// scanNetwork(_:) must trigger a scan, set isScanning=true, and be idempotent
// when already scanning. If scanNetwork() ever silently regresses, these fail.

@Suite(.serialized)
@MainActor
struct NetworkDetailViewScanRegressionTests {

    // MARK: - Helpers

    private func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }

    private func makeCoordinator(
        context: ModelContext,
        networkProfileManager: NetworkProfileManager = NetworkProfileManager()
    ) -> DeviceDiscoveryCoordinator {
        DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: networkProfileManager,
            // A holding fixture, never the production pipeline: these tests assert the
            // coordinator's scan lifecycle, not discovery. A real LAN scan started here used to
            // outlive the test and trap on its released ModelContainer (#309).
            pipelineFactory: { _ in
                ScanPipeline(steps: [ScanPipeline.Step(phases: [HoldingScanPhase()], concurrent: false)])
            }
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
        defer { withExtendedLifetime(container) {} }
        let coordinator = makeCoordinator(context: context)
        defer { coordinator.stopScan() }
        let profile = makeProfile(name: "HomeNet")

        coordinator.scanNetwork(profile)

        #expect(coordinator.networkProfile?.id == profile.id,
                "networkProfile must be updated — previously the stale closure never propagated the profile to the coordinator")
    }

    @Test("scanNetwork triggers isScanning=true")
    func scanNetworkTriggersIsScanning() throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let coordinator = makeCoordinator(context: context)
        defer { coordinator.stopScan() }

        #expect(coordinator.isScanning == false)
        coordinator.scanNetwork(makeProfile())
        #expect(coordinator.isScanning == true,
                "scanNetwork must set isScanning=true — if this fails the scan button is silently broken again")
    }

    @Test("scanNetwork while already scanning is idempotent")
    func scanNetworkWhileAlreadyScanningIsIdempotent() throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let coordinator = makeCoordinator(context: context)
        defer { coordinator.stopScan() }

        coordinator.scanNetwork(makeProfile(name: "Net1"))
        #expect(coordinator.isScanning == true)
        let progressAfterFirst = coordinator.scanProgress

        // A second call while scanning must not restart (guard !isScanning in startScan)
        coordinator.scanNetwork(makeProfile(name: "Net2"))
        #expect(coordinator.isScanning == true)
        #expect(coordinator.scanProgress == progressAfterFirst,
                "scanProgress must not reset when scanNetwork is called while already scanning")
    }

    @Test("scanNetwork for another network while scanning leaves the running scan's network in place (#353)")
    func scanNetworkWhileScanningDoesNotSwitchNetwork() throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let suite = "ScanMidScan-\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: { [] })
        let networkA = try #require(manager.addProfile(gateway: "10.1.0.1", subnet: "10.1.0.0/24", name: "A"))
        let networkB = try #require(manager.addProfile(gateway: "10.2.0.1", subnet: "10.2.0.0/24", name: "B"))
        let coordinator = makeCoordinator(context: context, networkProfileManager: manager)
        defer { coordinator.stopScan() }

        coordinator.scanNetwork(networkA)
        #expect(coordinator.isScanning)

        coordinator.scanNetwork(networkB)

        #expect(coordinator.networkProfile?.id == networkA.id,
                "The coordinator must keep reporting the network it is actually scanning")
        #expect(manager.activeProfile?.id == networkA.id,
                "A refused scan request must not move the ACTIVE network")
    }

    // MARK: - #358: scan the local network at launch

    private func makeLaunchManager(withLocal: Bool) -> (NetworkProfileManager, UserDefaults, String) {
        let suite = "LaunchScan-\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: suite)!
        let local = makeProfile(name: "Home")
        let manager = NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: { withLocal ? [local] : [] })
        return (manager, defaults, suite)
    }

    @Test("Launch scan scans the local network (#358)")
    func launchScanScansLocalNetwork() throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let (manager, defaults, suite) = makeLaunchManager(withLocal: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        let local = try #require(manager.profiles.first(where: { $0.isLocal }))
        let coordinator = makeCoordinator(context: context, networkProfileManager: manager)
        defer { coordinator.stopScan() }

        #expect(coordinator.startLaunchScan())
        #expect(coordinator.isScanning, "Launch must start a scan so the dashboard fills without pressing Scan")
        #expect(coordinator.networkProfile?.id == local.id)
    }

    @Test("Launch scan does nothing without a local network")
    func launchScanSkipsWithoutLocalNetwork() throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let (manager, defaults, suite) = makeLaunchManager(withLocal: false)
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = manager.addProfile(gateway: "10.9.0.1", subnet: "10.9.0.0/24", name: "Remote")
        let coordinator = makeCoordinator(context: context, networkProfileManager: manager)
        defer { coordinator.stopScan() }

        #expect(!coordinator.startLaunchScan())
        #expect(!coordinator.isScanning, "A remote manual network must not be scanned automatically")
    }

    @Test("Launch scan does not restart a scan that is already running")
    func launchScanLeavesRunningScanAlone() throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let (manager, defaults, suite) = makeLaunchManager(withLocal: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        let remote = try #require(manager.addProfile(gateway: "10.9.0.1", subnet: "10.9.0.0/24", name: "Remote"))
        let coordinator = makeCoordinator(context: context, networkProfileManager: manager)
        defer { coordinator.stopScan() }

        coordinator.scanNetwork(remote)
        let progress = coordinator.scanProgress

        #expect(!coordinator.startLaunchScan())
        #expect(coordinator.networkProfile?.id == remote.id)
        #expect(coordinator.scanProgress == progress)
    }

    @Test("stopScan clears isScanning so button re-enables")
    func stopScanClearsIsScanning() throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let coordinator = makeCoordinator(context: context)
        defer { coordinator.stopScan() }

        coordinator.scanNetwork(makeProfile())
        #expect(coordinator.isScanning == true)

        coordinator.stopScan()
        #expect(coordinator.isScanning == false,
                "stopScan must clear isScanning — UI button .disabled state depends on this")
    }

    @Test("scanProgress advances once scan task begins")
    func scanProgressAdvancesWhenScanBegins() async throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let coordinator = makeCoordinator(context: context)
        defer { coordinator.stopScan() }

        #expect(coordinator.scanProgress == 0.0)
        coordinator.scanNetwork(makeProfile())
        #expect(coordinator.isScanning == true)

        // Give scan task time to advance past the 0.1 progress checkpoint
        try await Task.sleep(for: .milliseconds(300))
        #expect(coordinator.scanProgress > 0.0,
                "scanProgress must advance — the UI ProgressView depends on this value")

        coordinator.stopScan()
    }

    // MARK: - #347: the panel's Scan button targets the panel's own network

    @Test("Panel for network B scans B even after A was scanned last")
    func panelScanTargetsItsOwnNetwork() {
        let networkA = makeProfile(name: "A")
        let networkB = makeProfile(name: "B")

        let target = NetworkDevicesPanel.scanTarget(
            panelProfileID: networkB.id,
            profiles: [networkA, networkB],
            lastScanned: networkA
        )

        #expect(target == .network(networkB),
                "Scan in B's panel must scan B, not the last-scanned network A")
    }

    @Test("Panel for an unknown network does not scan another network")
    func panelScanWithUnknownProfileDoesNothing() {
        let networkA = makeProfile(name: "A")

        let target = NetworkDevicesPanel.scanTarget(
            panelProfileID: UUID(),
            profiles: [networkA],
            lastScanned: networkA
        )

        #expect(target == NetworkDevicesPanel.ScanTarget.none)
    }

    @Test("Global panel (nil ID) rescans the last-scanned network")
    func globalPanelRescansLastScanned() {
        let networkA = makeProfile(name: "A")
        let networkB = makeProfile(name: "B")

        let target = NetworkDevicesPanel.scanTarget(
            panelProfileID: nil,
            profiles: [networkA, networkB],
            lastScanned: networkA
        )

        #expect(target == .network(networkA))
    }

    @Test("Global panel (nil ID) with nothing scanned starts a default scan")
    func globalPanelStartsDefaultScan() {
        let target = NetworkDevicesPanel.scanTarget(
            panelProfileID: nil,
            profiles: [makeProfile(name: "A")],
            lastScanned: nil
        )

        #expect(target == .startScan)
    }
}

// MARK: - Fixture

/// Reports a little progress, then holds the scan open until cancelled, so `isScanning`
/// and `scanProgress` can be asserted without any network activity.
private struct HoldingScanPhase: ScanPhase, Sendable {
    let id: ScanPhaseID = "fixtureHold"
    let displayName = "Fixture hold"
    let weight: Double = 1.0

    func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        await onProgress(0.1)
        try? await Task.sleep(for: .seconds(30))  // returns immediately on cancellation
    }
}
