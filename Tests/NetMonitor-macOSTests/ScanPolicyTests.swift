import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_macOS

/// A phase that holds the scan open until it's cancelled.
private struct HoldPolicyScanPhase: ScanPhase, Sendable {
    let id: ScanPhaseID = "scanPolicyHold"
    let displayName = "Hold"
    let weight: Double = 1.0
    func execute(context: ScanContext, accumulator: ScanAccumulator, onProgress: @Sendable (Double) async -> Void) async {
        try? await Task.sleep(for: .seconds(30))
    }
}

private func makePolicyProfile(name: String, isLocal: Bool) -> NetworkProfile {
    NetworkProfile(
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
        name: name,
        gatewayIP: "192.168.1.1",
        subnet: "192.168.1.0/24",
        isLocal: isLocal,
        discoveryMethod: isLocal ? .auto : .manual
    )
}

/// #484: one policy maps a scan reason and the coordinator's state to a target and an action.
struct ScanPolicyTests {
    private let local = makePolicyProfile(name: "Home", isLocal: true)
    private let remote = makePolicyProfile(name: "Office", isLocal: false)
    private let picked = makePolicyProfile(name: "Picked", isLocal: false)

    /// A case's label doubles as its table-row name in failures.
    private enum AutomaticReason: CaseIterable {
        case launch, periodic, menuBar, companion
        var reason: ScanReason {
            switch self {
            case .launch: .launch
            case .periodic: .periodic
            case .menuBar: .menuBar
            case .companion: .companion
            }
        }
    }

    @Test("Launch, periodic, menu bar and companion scan the local network, whatever was scanned last")
    func automaticReasonsTargetTheLocalNetwork() {
        for automatic in AutomaticReason.allCases {
            for current in [local, remote, nil] {
                #expect(
                    ScanPolicy.decide(automatic.reason, isScanning: false, local: local, current: current) == .start(local),
                    "\(automatic) with current \(current?.name ?? "none")"
                )
            }
        }
    }

    /// #628 (Devin review on #633): a replacement scans the manual network the dropped scan scanned,
    /// else the local network; never while a scan runs.
    @Test("A replacement keeps a manual network, else scans the local one")
    func replacementKeepsAManualNetwork() {
        #expect(ScanPolicy.decide(.replacement(manual: picked), isScanning: false, local: local, current: picked) == .start(picked))
        #expect(ScanPolicy.decide(.replacement(manual: nil), isScanning: false, local: local, current: remote) == .start(local))
        #expect(ScanPolicy.decide(.replacement(manual: picked), isScanning: true, local: local, current: picked) == .ignore)
        #expect(ScanPolicy.decide(.replacement(manual: nil), isScanning: false, local: nil, current: nil) == .ignore)
    }

    @Test("Those reasons are ignored while a scan runs, and when there is no local network")
    func automaticReasonsIgnored() {
        for automatic in AutomaticReason.allCases {
            for current in [local, remote, nil] {
                #expect(ScanPolicy.decide(automatic.reason, isScanning: true, local: local, current: current) == .ignore, "\(automatic) scanning")
                #expect(ScanPolicy.decide(automatic.reason, isScanning: false, local: nil, current: current) == .ignore, "\(automatic) no local")
                #expect(ScanPolicy.decide(automatic.reason, isScanning: true, local: nil, current: current) == .ignore, "\(automatic) scanning, no local")
            }
        }
    }

    @Test("A network change starts a local scan when idle and replaces a running scan")
    func networkChanged() {
        for current in [local, remote, nil] {
            #expect(ScanPolicy.decide(.networkChanged, isScanning: false, local: local, current: current) == .start(local))
            #expect(ScanPolicy.decide(.networkChanged, isScanning: true, local: local, current: current) == .replace(local))
            #expect(ScanPolicy.decide(.networkChanged, isScanning: false, local: nil, current: current) == .ignore)
            #expect(ScanPolicy.decide(.networkChanged, isScanning: true, local: nil, current: current) == .ignore)
        }
    }

    @Test("A user scan targets the network asked for, else the current one, and waits for a running scan")
    func userScans() {
        for localProfile in [local, nil] {
            for current in [local, remote, nil] {
                #expect(ScanPolicy.decide(.user(picked), isScanning: false, local: localProfile, current: current) == .start(picked))
                #expect(ScanPolicy.decide(.user(nil), isScanning: false, local: localProfile, current: current) == .start(current))
                #expect(ScanPolicy.decide(.user(picked), isScanning: true, local: localProfile, current: current) == .ignore)
                #expect(ScanPolicy.decide(.user(nil), isScanning: true, local: localProfile, current: current) == .ignore)
            }
        }
    }

    @Test("Only user scans count toward the review prompt")
    func reviewPromptCounting() {
        #expect(ScanReason.user(nil).countsTowardReviewPrompt)
        #expect(ScanReason.user(picked).countsTowardReviewPrompt)
        for automatic in AutomaticReason.allCases {
            #expect(!automatic.reason.countsTowardReviewPrompt)
        }
        #expect(!ScanReason.networkChanged.countsTowardReviewPrompt)
    }
}

/// #484: the coordinator applies the policy, so background scans return to the local network.
@MainActor
struct ScanPolicyCoordinatorTests {
    private func makeCoordinator(
        local: NetworkProfile,
        defaults: UserDefaults
    ) throws -> (DeviceDiscoveryCoordinator, NetworkProfileManager, ModelContainer) {
        let manager = NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: { [local] })
        let schema = Schema([LocalDevice.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: container.mainContext,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: manager,
            pipelineFactory: { _ in ScanPipeline(steps: [ScanPipeline.Step(phases: [HoldPolicyScanPhase()], concurrent: false)]) },
            scanHistory: .forTesting(),
            dispatcher: DeviceEventDispatcher()
        )
        return (coordinator, manager, container)
    }

    @Test("After a remote network was scanned, periodic, menu bar and companion rescans scan the local network")
    func backgroundRescansReturnToTheLocalNetwork() throws {
        let suite = "ScanPolicyCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let local = makePolicyProfile(name: "Home", isLocal: true)
        let (coordinator, manager, container) = try makeCoordinator(local: local, defaults: defaults)
        defer { withExtendedLifetime(container) {} }
        defer { coordinator.stopScan() }
        let localID = try #require(manager.localProfile?.id)
        let remote = try #require(manager.addProfile(gateway: "10.20.0.1", subnet: "10.20.0.0/24", name: "Office"))

        for reason in [ScanReason.periodic, .menuBar, .companion] {
            coordinator.rescan(.user(remote))
            coordinator.stopScan()
            #expect(coordinator.networkProfile?.id == remote.id, "The remote network was scanned last")

            #expect(coordinator.rescan(reason))
            #expect(coordinator.isScanning)
            #expect(coordinator.networkProfile?.id == localID, "\(reason) must scan the local network")
            coordinator.stopScan()
        }
    }

    @Test("A network change replaces a running scan of another network; a periodic rescan leaves it alone")
    func networkChangeReplacesButPeriodicDoesNot() throws {
        let suite = "ScanPolicyCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let local = makePolicyProfile(name: "Home", isLocal: true)
        let (coordinator, manager, container) = try makeCoordinator(local: local, defaults: defaults)
        defer { withExtendedLifetime(container) {} }
        defer { coordinator.stopScan() }
        let localID = try #require(manager.localProfile?.id)
        let remote = try #require(manager.addProfile(gateway: "10.20.0.1", subnet: "10.20.0.0/24", name: "Office"))

        coordinator.rescan(.user(remote))
        #expect(!coordinator.rescan(.periodic))
        #expect(coordinator.networkProfile?.id == remote.id, "A periodic rescan must not disturb a running scan")

        #expect(coordinator.rescan(.networkChanged))
        #expect(coordinator.isScanning)
        #expect(coordinator.networkProfile?.id == localID)
    }
}

/// #484: logs name the reason, never the network profile.
struct ScanReasonLogLabelTests {
    @Test func labelsCarryNoNetworkDetails() {
        let profile = NetworkProfile(
            interfaceName: "en0", ipAddress: "192.168.1.10",
            network: NetworkUtilities.IPv4Network(
                networkAddress: 0xC0A80100, broadcastAddress: 0xC0A801FF, interfaceAddress: 0xC0A8010A, netmask: 0xFFFFFF00
            ),
            connectionType: .wifi, name: "Home", gatewayIP: "192.168.1.1", subnet: "192.168.1.0/24",
            isLocal: true, discoveryMethod: .auto
        )
        #expect(ScanReason.user(profile).logLabel == "user")
        #expect(ScanReason.periodic.logLabel == "periodic")
    }
}
