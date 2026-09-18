import Foundation
import SwiftData
import Testing
import NetMonitorCore
import NetworkScanKit
@testable import NetMonitor_macOS

@Suite(.serialized)
@MainActor
struct DeviceDiscoveryCoordinatorTests {

    @Test func mergeDiscoveredDevicesUpdatesExistingRecordByMACAndInsertsNewDevice() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let existing = LocalDevice(
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: nil
        )
        existing.status = .offline
        context.insert(existing)
        try context.save()

        let coordinator = makeCoordinator(context: context)
        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(
                ipAddress: "192.168.1.11",
                macAddress: "aa:bb:cc:dd:ee:ff",
                hostname: "printer.local"
            ),
            LocalDiscoveredDevice(
                ipAddress: "192.168.1.20",
                macAddress: "",
                hostname: "camera.local"
            )
        ], profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 2)

        let updated = devices.first { $0.macAddress == "AA:BB:CC:DD:EE:FF" }
        #expect(updated?.ipAddress == "192.168.1.11")
        #expect(updated?.hostname == "printer.local")
        #expect(updated?.status == .online)

        let inserted = devices.first { $0.ipAddress == "192.168.1.20" }
        #expect(inserted != nil)
        #expect(inserted?.hostname == "camera.local")
    }

    @Test func mergeDiscoveredDevicesToleratesDuplicateHistoricalIdentifiers() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        context.insert(LocalDevice(
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "old-one.local"
        ))
        context.insert(LocalDevice(
            ipAddress: "192.168.1.11",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "old-two.local"
        ))
        try context.save()

        let coordinator = makeCoordinator(context: context)
        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(
                ipAddress: "192.168.1.12",
                macAddress: "aa:bb:cc:dd:ee:ff",
                hostname: "current.local"
            )
        ], profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 2)
        #expect(devices.contains { $0.hostname == "current.local" && $0.ipAddress == "192.168.1.12" })
    }

    @Test func markOfflineDevicesMarksOnlyMissingIPsOffline() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let coordinator = makeCoordinator(context: context)
        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.168.1.2", macAddress: "00:00:00:00:00:02", hostname: nil),
            LocalDiscoveredDevice(ipAddress: "192.168.1.3", macAddress: "00:00:00:00:00:03", hostname: nil)
        ], profileID: nil)
        coordinator.markOfflineDevices(currentIPs: Set(["192.168.1.2"]), profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        let stillOnline = devices.first { $0.ipAddress == "192.168.1.2" }
        let nowOffline = devices.first { $0.ipAddress == "192.168.1.3" }

        #expect(stillOnline?.status == .online)
        #expect(nowOffline?.status == .offline)
    }

    // MARK: - #279 equivalence: fixture devices through the retained merge/offline path
    //
    // This exercises only `mergeDiscoveredDevices`/`markOfflineDevices`, whose bodies are
    // unchanged by #279's `ScanEngine` adapter rewrite, so it must be green on both the
    // pre-rewrite ARP/Bonjour coordinator and the post-rewrite `ScanEngine` adapter.

    @Test func fixtureDevicesThroughMergeAndMarkOfflineMatchGoldenRows() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let coordinator = makeCoordinator(context: context)
        coordinator.mergeDiscoveredDevices(DeviceDiscoveryCoordinatorFixtures.discovered, profileID: nil)
        coordinator.markOfflineDevices(
            currentIPs: DeviceDiscoveryCoordinatorFixtures.currentIPsAfterOffline,
            profileID: nil
        )

        let rows = try context.fetch(FetchDescriptor<LocalDevice>())
            .map {
                DeviceDiscoveryCoordinatorFixtures.Row(
                    ipAddress: $0.ipAddress,
                    macAddress: $0.macAddress,
                    hostname: $0.hostname,
                    vendor: $0.vendor,
                    status: $0.status,
                    lastLatency: $0.lastLatency
                )
            }
            .sorted { $0.ipAddress < $1.ipAddress }

        #expect(rows == DeviceDiscoveryCoordinatorFixtures.expectedRows.sorted { $0.ipAddress < $1.ipAddress })
    }

    // MARK: - #279 equivalence: ScanEngine's DiscoveredDevice mapped through the new
    // mapping function, then the same retained merge/offline path.

    @Test func mappedEngineDevicesThroughMergeAndMarkOfflineMatchGoldenRows() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let coordinator = makeCoordinator(context: context)
        let mapped = DeviceDiscoveryCoordinator.mapDiscoveredDevices(DeviceDiscoveryCoordinatorFixtures.engineDiscovered)
        coordinator.mergeDiscoveredDevices(mapped, profileID: nil)
        coordinator.markOfflineDevices(
            currentIPs: DeviceDiscoveryCoordinatorFixtures.currentIPsAfterOffline,
            profileID: nil
        )

        let rows = try context.fetch(FetchDescriptor<LocalDevice>())
            .map {
                DeviceDiscoveryCoordinatorFixtures.Row(
                    ipAddress: $0.ipAddress,
                    macAddress: $0.macAddress,
                    hostname: $0.hostname,
                    vendor: $0.vendor,
                    status: $0.status,
                    lastLatency: $0.lastLatency
                )
            }
            .sorted { $0.ipAddress < $1.ipAddress }

        #expect(rows == DeviceDiscoveryCoordinatorFixtures.expectedRows.sorted { $0.ipAddress < $1.ipAddress })
    }

    // MARK: - #279 equivalence: startScan() end to end with a fixture pipeline

    @Test func startScanWithFixturePipelineProducesGoldenRowsAcrossTwoScans() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        // Scan A discovers all four devices; scan B omits one, so markOfflineDevices
        // (whose currentIPs is derived from THIS scan's results) flips it to .offline —
        // exercising the same offline transition the merge-only fixture test covers.
        let upsertDevices = FixtureUpsertBox(devices: DeviceDiscoveryCoordinatorFixtures.endToEndDevicesScanA)

        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context,
            arpScanner: ARPScannerService(timeout: 0.05),
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(),
            pipelineFactory: { _, _ in
                ScanPipeline(steps: [
                    ScanPipeline.Step(phases: [FixtureUpsertScanPhase(box: upsertDevices)], concurrent: false)
                ])
            },
            portChecker: { _, _, _ in false }
        )

        // Each scan's post-engine steps include the retained, non-injectable shell-ping
        // `measureDeviceLatencies` (D14): `/sbin/ping -c 3 -W 2000 <ip>`, whose runner
        // timeout is `2 * 3 + 5` = 11s per device, run concurrently across this fixture's
        // devices but still real wall-clock time against unroutable TEST-NET-1 addresses.
        // Give each scan a generous bound rather than racing that.
        coordinator.startScan()
        await Self.waitUntil(timeout: .seconds(30)) { coordinator.isScanning == false }
        #expect(coordinator.isScanning == false)

        upsertDevices.devices = DeviceDiscoveryCoordinatorFixtures.endToEndDevicesScanB
        coordinator.startScan()
        await Self.waitUntil(timeout: .seconds(30)) { coordinator.isScanning == false }
        #expect(coordinator.isScanning == false)

        let rows = try context.fetch(FetchDescriptor<LocalDevice>())
            .map {
                DeviceDiscoveryCoordinatorFixtures.Row(
                    ipAddress: $0.ipAddress,
                    macAddress: $0.macAddress,
                    hostname: $0.hostname,
                    vendor: $0.vendor,
                    status: $0.status,
                    lastLatency: $0.lastLatency
                )
            }
            .sorted { $0.ipAddress < $1.ipAddress }

        #expect(rows == DeviceDiscoveryCoordinatorFixtures.expectedRowsAfterEndToEndScans.sorted { $0.ipAddress < $1.ipAddress })
    }

    // MARK: - #279 cancellation

    @Test func stopScanDuringFixturePhaseReleasesConnectionBudgetAndStopsScanning() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context,
            arpScanner: ARPScannerService(timeout: 0.05),
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(),
            pipelineFactory: { _, _ in
                ScanPipeline(steps: [
                    ScanPipeline.Step(phases: [FixtureSleepingScanPhase()], concurrent: false)
                ])
            },
            portChecker: { _, _, _ in false }
        )

        coordinator.startScan()
        // Give the fixture phase a moment to start sleeping and acquire its connection slot.
        try? await Task.sleep(for: .milliseconds(100))
        coordinator.stopScan()

        await Self.waitUntil { coordinator.isScanning == false }
        #expect(coordinator.isScanning == false)

        // ScanEngine's per-phase timeout race resolves (and the phase's task returns)
        // as soon as its cancellation handler fires, which can be before the phase's own
        // `operationTask` — and therefore its `withConnectionSlot` release — has actually
        // unwound. Poll instead of asserting once to avoid racing that unwind.
        await Self.waitUntil(timeout: .seconds(10)) { await ConnectionBudget.shared.activeCount == 0 }
        #expect(await ConnectionBudget.shared.activeCount == 0)
    }

    /// Polls `condition` until it's true or `timeout` elapses — used instead of a fixed
    /// sleep so these tests complete as soon as the coordinator's scan task actually
    /// finishes, without reaching into its `private` `scanTask`. `condition` may itself
    /// `await` actor-isolated state (e.g. `ConnectionBudget.shared.activeCount`); a plain
    /// synchronous closure is also accepted since a sync closure trivially satisfies an
    /// `async` closure parameter.
    private static func waitUntil(timeout: Duration = .seconds(10), _ condition: () async -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while await !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func makeCoordinator(context: ModelContext) -> DeviceDiscoveryCoordinator {
        DeviceDiscoveryCoordinator(
            modelContext: context,
            arpScanner: ARPScannerService(timeout: 0.05),
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager()
        )
    }

    private func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }
}

// MARK: - Fixture ScanPhases

/// Mutable holder for `FixtureUpsertScanPhase`'s device list, reassigned between the two
/// scans in `startScanWithFixturePipelineProducesGoldenRowsAcrossTwoScans`. Mutation only
/// ever happens on the MainActor test body between scans (each awaited to completion via
/// `waitUntil` before the next `startScan()`), never concurrently with a running scan, so
/// `@unchecked Sendable` is safe here.
private final class FixtureUpsertBox: @unchecked Sendable {
    var devices: [DiscoveredDevice]
    init(devices: [DiscoveredDevice]) {
        self.devices = devices
    }
}

/// Test-only `ScanPhase` that upserts a fixed set of devices into the accumulator — used
/// to drive `startScan()` deterministically without touching any live network, mirroring
/// what `ScanEngine`'s real ARP/Bonjour/TCP/SSDP phases would produce.
private struct FixtureUpsertScanPhase: ScanPhase, Sendable {
    let id: ScanPhaseID = "fixtureUpsert"
    let displayName = "Fixture upsert"
    let weight: Double = 1.0
    let box: FixtureUpsertBox

    func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        await onProgress(0.0)
        for device in box.devices {
            await accumulator.upsert(device)
        }
        await onProgress(1.0)
    }
}

/// Test-only `ScanPhase` that sleeps while holding a `ConnectionBudget` slot — used to
/// exercise `stopScan()` cancellation and prove the slot is released even under
/// cancellation, the same way every real raw-socket / `NWConnection` phase must.
private struct FixtureSleepingScanPhase: ScanPhase, Sendable {
    let id: ScanPhaseID = "fixtureSleep"
    let displayName = "Fixture sleep"
    let weight: Double = 1.0

    func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        await onProgress(0.0)
        _ = await withConnectionSlot { () -> Bool in
            try? await Task.sleep(for: .seconds(30))
            return true
        }
        await onProgress(1.0)
    }
}
