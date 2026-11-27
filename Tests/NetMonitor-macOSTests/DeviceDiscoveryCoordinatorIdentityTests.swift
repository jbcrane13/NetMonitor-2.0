import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_macOS

/// #628 PR B: on the Mac, a scan is saved to device rows only once the same-subnet network it ran on
/// is identified by its router hint; while it isn't, the network's saved rows read as history.
@Suite("DeviceDiscoveryCoordinator network identity (#628 PR B)", .serialized)
@MainActor
struct DeviceDiscoveryCoordinatorIdentityTests {
    let keyA = RouterKey(["aaaa"])
    let keyB = RouterKey(["bbbb"])
    private let base = DeviceDiscoveryCoordinatorReconcileTests()

    final class Box: @unchecked Sendable {
        var hint: RouterHintStatus = .absent
        var detections = 0
        var devices: [DiscoveredDevice] = []
        /// Holds the fixture scan until released, to act while the probe runs.
        var holds = false
        var gate: CheckedContinuation<Void, Never>?

        @MainActor
        func scan() async -> [DiscoveredDevice] {
            if holds {
                await withCheckedContinuation { gate = $0 }
            }
            return devices
        }
    }

    struct FixturePhase: ScanPhase, Sendable {
        let id: ScanPhaseID = "identityFixture"
        let displayName = "Identity fixture"
        let weight: Double = 1.0
        let devices: @Sendable () async -> [DiscoveredDevice]

        func execute(context: ScanContext, accumulator: ScanAccumulator, onProgress: @Sendable (Double) async -> Void) async {
            for device in await devices() {
                await accumulator.upsert(device)
            }
            await onProgress(1)
        }
    }

    @MainActor
    struct Setup {
        let coordinator: DeviceDiscoveryCoordinator
        let identity: NetworkIdentityController
        let manager: NetworkProfileManager
        let join: NetworkJoinClock
        let context: ModelContext
        let container: ModelContainer
        var local: UUID { manager.localProfile?.id ?? UUID() }
    }

    private func setUp(_ box: Box, legacy: [String: UUID] = [:]) throws -> Setup {
        let (container, context) = try base.makeStore()
        let live = NetworkProfile(
            interfaceName: "en0", ipAddress: "192.168.1.10",
            network: NetworkUtilities.IPv4Network(
                networkAddress: 0xC0A8_0100, broadcastAddress: 0xC0A8_01FF, interfaceAddress: 0xC0A8_010A, netmask: 0xFFFF_FF00
            ),
            connectionType: .wifi
        )
        let manager = NetworkProfileManager(userDefaults: InMemoryDefaults(), activeProfilesProvider: { [live] })
        let join = NetworkJoinClock.forTests
        let dir = FileManager.default.temporaryDirectory.appending(path: "mac-identity-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = NetworkIdentityStore(directory: dir, defaults: InMemoryDefaults(), legacyNetworks: { legacy }, reservedIDs: { [] })
        let devices = box
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: manager,
            pipelineFactory: { _ in
                let phase = FixturePhase(devices: { await devices.scan() })
                return ScanPipeline(steps: [ScanPipeline.Step(phases: [phase], concurrent: false)])
            },
            portChecker: { _, _, _ in false },
            scanHistory: .forTesting(),
            dispatcher: DeviceEventDispatcher(),
            joinClock: join,
            gatewayIP: { "192.168.1.1" }
        )
        let identity = NetworkIdentityController(
            store: store, clock: join, launchID: UUID(), readHint: { _ in box.hint },
            probe: { [weak coordinator] legacy, _ in await coordinator?.identificationProbe(legacy: legacy) },
            requestDetection: { box.detections += 1 }
        )
        coordinator.identity = identity
        manager.localNetworkIdentity = { identity.resolveID(group: $0, defaultID: $1) }
        manager.detectLocalNetwork()
        return Setup(coordinator: coordinator, identity: identity, manager: manager, join: join, context: context, container: container)
    }

    private func row(_ setup: Setup, _ ip: String, _ name: String) throws -> LocalDevice {
        let row = LocalDevice(ipAddress: ip, macAddress: "", hostname: name, networkProfileID: setup.local)
        setup.context.insert(row)
        try setup.context.save()
        return row
    }

    @Test func aScanWhileTheQuestionIsOpenIsNotSavedAndTheRowsAreHistory() throws {
        let box = Box()
        box.hint = .present(keyA)
        let setup = try setUp(box)
        let home = setup.local
        _ = try row(setup, "192.168.1.20", "office-printer")
        _ = setup.coordinator.commitScan(
            [DeviceDiscoveryCoordinatorReconcileTests.engine("192.168.1.20", "office-printer")], profileID: home, now: Date(),
            token: setup.join.token(for: nil)
        )
        #expect(setup.coordinator.lastScanTime(for: home) != nil)

        // Another router on the same subnet: which network is this?
        box.hint = .present(keyB)
        setup.manager.detectLocalNetwork()
        #expect(setup.identity.question == .whichNetwork(group: NetworkGroup(interface: "en0", subnet: "192.168.1.0/24"), key: keyB, options: [home]))
        let commit = setup.coordinator.commitScan(
            [DeviceDiscoveryCoordinatorReconcileTests.engine("192.168.1.20", "someone-elses-printer")], profileID: home,
            now: Date().addingTimeInterval(60), token: setup.join.token(for: nil)
        )
        #expect(commit == .held)
        #expect(try setup.context.fetch(FetchDescriptor<LocalDevice>()).map(\.hostname) == ["office-printer"])
        #expect(setup.coordinator.replacementScans.attempts == 0)
        let presence = setup.coordinator.presence()
        #expect(presence.isHeld(home))
        let saved = try #require(setup.coordinator.discoveredDevices.first)
        #expect(presence.freshness(of: saved) == .notCheckedRecently)
    }

    /// Ask reads the network's last scan through the held snapshot: a held network has none (#645).
    @Test func askSeesNoCurrentScanForAHeldNetwork() throws {
        let box = Box()
        box.hint = .present(keyA)
        let setup = try setUp(box)
        let home = setup.local
        _ = try row(setup, "192.168.1.20", "office-printer")
        _ = setup.coordinator.commitScan(
            [DeviceDiscoveryCoordinatorReconcileTests.engine("192.168.1.20", "office-printer")], profileID: home, now: Date(),
            token: setup.join.token(for: nil)
        )
        #expect(setup.coordinator.presentedLastScan(for: home) != nil)
        box.hint = .present(keyB)
        setup.manager.detectLocalNetwork()
        #expect(setup.coordinator.presentedLastScan(for: home) == nil)
        #expect(setup.coordinator.lastScanTime(for: home) != nil, "the record itself stays")
    }

    /// The Mac moves to a same-subnet site with no path update: the commit's router re-read catches
    /// it, holds the rows at once, and asks for one detection.
    @Test func aRouterMismatchAtCommitWithNoPathEventHoldsTheRowsAndAsksForOneDetection() throws {
        let box = Box()
        box.hint = .present(keyA)
        let setup = try setUp(box)
        let home = setup.local
        _ = try row(setup, "192.168.1.20", "office-printer")

        box.hint = .present(keyB)
        let token = setup.join.token(for: nil)
        let commit = setup.coordinator.commitScan(
            [DeviceDiscoveryCoordinatorReconcileTests.engine("192.168.1.20", "someone-elses-printer")], profileID: home, now: Date(), token: token
        )
        #expect(commit == .held)
        #expect(setup.coordinator.presence().isHeld(home))
        #expect(try setup.context.fetch(FetchDescriptor<LocalDevice>()).map(\.hostname) == ["office-printer"])
        _ = setup.coordinator.commitScan([], profileID: home, now: Date(), token: token)
        #expect(box.detections == 1)
    }

    /// Detail probes (ping, ports, services) take a token on the row's network: refused while held.
    @Test func aDetailProbeOnAHeldNetworkMayNotWrite() throws {
        let box = Box()
        box.hint = .present(keyA)
        let setup = try setUp(box)
        let home = setup.local
        #expect(setup.coordinator.mayWrite(setup.join.token(for: home)))
        box.hint = .present(keyB)
        setup.manager.detectLocalNetwork()
        #expect(!setup.coordinator.mayWrite(setup.join.token(for: home)))
        let question = try #require(setup.identity.question)
        setup.identity.answer(.same(home), to: question)
        setup.manager.detectLocalNetwork()
        #expect(setup.coordinator.mayWrite(setup.join.token(for: home)))
    }

    /// A network that settles after a hold is scanned once: the held scan saved nothing.
    @Test func identificationSettlingStartsOneScan() async throws {
        let box = Box()
        box.hint = .present(keyA)
        let setup = try setUp(box)
        let home = setup.local
        box.hint = .present(keyB)
        setup.manager.detectLocalNetwork()
        let question = try #require(setup.identity.question)
        box.devices = [DeviceDiscoveryCoordinatorReconcileTests.engine("192.168.1.20", "office-printer")]
        setup.identity.answer(.same(home), to: question)
        #expect(!setup.coordinator.isScanning)
        setup.manager.detectLocalNetwork()
        await waitUntil { setup.coordinator.lastScanTime(for: home) != nil }
        #expect(setup.coordinator.lastScanTime(for: home) != nil)
    }

    /// A legacy network with no saved devices has no history to mix: it binds quietly.
    @Test func aLegacyNetworkWithNoSavedDevicesIsClear() async throws {
        let box = Box()
        let legacy = UUID()
        let setup = try setUp(box, legacy: ["en0|192.168.1.0/24": legacy])
        box.devices = [DeviceDiscoveryCoordinatorReconcileTests.engine("192.168.1.1", "rt-ax86u-7c10")]
        #expect(await setup.coordinator.identificationProbe(legacy: legacy) == true)
    }

    /// A scan asked for while the probe runs is refused (it would save nothing), and one runs once the
    /// network is identified (#645).
    @Test func aScanAskedForDuringIdentificationIsRefusedAndOneFollows() async throws {
        let box = Box()
        let legacy = UUID()
        box.hint = .present(keyA)
        box.holds = true
        let setup = try setUp(box, legacy: ["en0|192.168.1.0/24": legacy])
        #expect(setup.coordinator.isIdentifyingNetwork)
        await waitUntil { box.gate != nil }
        #expect(!setup.coordinator.rescan(.user(nil)))
        #expect(!setup.coordinator.rescan(.launch))
        #expect(!setup.coordinator.isScanning)

        box.holds = false
        box.devices = [DeviceDiscoveryCoordinatorReconcileTests.engine("192.168.1.20", "office-printer")]
        box.gate?.resume()
        await setup.identity.probeTask?.value
        #expect(setup.identity.authorizes(legacy))
        await waitUntil { setup.coordinator.lastScanTime(for: legacy) != nil }
        #expect(setup.coordinator.lastScanTime(for: legacy) != nil)
    }

    /// The identification probe scans and compares, and never reconciles, records or publishes.
    @Test func theIdentificationProbeNeverWrites() async throws {
        let box = Box()
        let legacy = UUID()
        box.hint = .absent
        let setup = try setUp(box, legacy: ["en0|192.168.1.0/24": legacy])
        let saved = [("192.168.1.1", "rt-ax86u-7c10"), ("192.168.1.20", "office-printer"), ("192.168.1.30", "backup-nas")]
        for (ip, name) in saved {
            let row = LocalDevice(ipAddress: ip, macAddress: "", hostname: name, networkProfileID: legacy)
            row.lastSeen = Date(timeIntervalSince1970: 1_000)
            setup.context.insert(row)
        }
        try setup.context.save()
        box.devices = saved.map { DeviceDiscoveryCoordinatorReconcileTests.engine($0.0, $0.1) }

        let clear = await setup.coordinator.identificationProbe(legacy: legacy)
        #expect(clear == true)
        let rows = try setup.context.fetch(FetchDescriptor<LocalDevice>())
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.lastSeen == Date(timeIntervalSince1970: 1_000) })
        #expect(setup.coordinator.lastScanTime(for: legacy) == nil)

        box.devices = [DeviceDiscoveryCoordinatorReconcileTests.engine("192.168.1.1", "another-router")]
        #expect(await setup.coordinator.identificationProbe(legacy: legacy) == false)
    }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
