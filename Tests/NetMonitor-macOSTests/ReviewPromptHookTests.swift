import Foundation
import SwiftData
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS
import NetworkScanKit

/// Completed user-started scans feed ``ReviewPromptPolicy`` (#337); the automatic
/// launch scan and scans requested by the iPhone companion do not.
@Suite(.serialized)
@MainActor
struct ReviewPromptHookTests {

    private final class Harness {
        let suiteName = "ReviewPromptHookTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        var prompts = 0

        init() {
            // swiftlint:disable:next force_unwrapping
            defaults = UserDefaults(suiteName: suiteName)!
        }

        @MainActor
        lazy var policy = ReviewPromptPolicy(defaults: defaults, appVersion: "test") { [weak self] in
            self?.prompts += 1
            return true
        }

        deinit {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }

    private func makeCoordinator(context: ModelContext, harness: Harness) -> DeviceDiscoveryCoordinator {
        let local = NetworkProfile(
            id: UUID(),
            interfaceName: "en0",
            ipAddress: "192.168.1.10",
            network: NetworkUtilities.IPv4Network(
                networkAddress: 0xC0A80100,
                broadcastAddress: 0xC0A801FF,
                interfaceAddress: 0xC0A80101,
                netmask: 0xFFFFFF00
            ),
            connectionType: .wifi,
            name: "Home",
            gatewayIP: "192.168.1.1",
            subnet: "192.168.1.0/24",
            isLocal: true,
            discoveryMethod: .auto
        )
        return DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(userDefaults: harness.defaults, activeProfilesProvider: { [local] }),
            // Empty pipeline: scans complete immediately, no real LAN scan (#309).
            pipelineFactory: { _ in ScanPipeline(steps: []) },
            reviewPrompt: harness.policy
        )
    }

    private func finish(_ coordinator: DeviceDiscoveryCoordinator) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while coordinator.isScanning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func userScansPromptOnTheThirdCompletedScan() async throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let harness = Harness()
        let coordinator = makeCoordinator(context: context, harness: harness)
        defer { coordinator.stopScan() }

        coordinator.startScan()
        await finish(coordinator)
        let local = try #require(coordinator.networkProfileManager.profiles.first(where: { $0.isLocal }))
        coordinator.scanNetwork(local)
        await finish(coordinator)
        #expect(harness.prompts == 0)

        coordinator.startScan()
        await finish(coordinator)
        #expect(harness.prompts == 1)
    }

    @Test func launchAndCompanionScansDoNotCount() async throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let harness = Harness()
        let coordinator = makeCoordinator(context: context, harness: harness)
        defer { coordinator.stopScan() }

        for _ in 0..<3 {
            #expect(coordinator.startLaunchScan())
            await finish(coordinator)
            coordinator.startScan(countsTowardReviewPrompt: false)
            await finish(coordinator)
        }

        #expect(harness.prompts == 0)
    }

    @Test func cancelledScanDoesNotCount() async throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let harness = Harness()
        harness.defaults.set(ReviewPromptPolicy.scanThreshold - 1, forKey: "reviewPrompt_completedScanCount")
        let coordinator = makeCoordinator(context: context, harness: harness)

        coordinator.startScan()
        coordinator.stopScan()
        try await Task.sleep(for: .milliseconds(200))

        #expect(harness.prompts == 0)
    }
}
