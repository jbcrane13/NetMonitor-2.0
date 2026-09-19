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
                    lastLatency: $0.lastLatency,
                    openPorts: $0.openPorts
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
                    lastLatency: $0.lastLatency,
                    openPorts: $0.openPorts
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
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(),
            // Opts out of enrichment explicitly (E9): a fixture pipeline that ignores
            // `ScanPipelineInputs.standardEnrichmentStep` never invokes `portChecker` or
            // `pingRunner`, so this scan is fully hermetic — no shell-out, no real network.
            pipelineFactory: { _ in
                ScanPipeline(steps: [
                    ScanPipeline.Step(phases: [FixtureUpsertScanPhase(box: upsertDevices)], concurrent: false)
                ])
            },
            portChecker: { _, _, _ in false }
        )

        coordinator.startScan()
        await waitUntil(timeout: .seconds(30)) { coordinator.isScanning == false }
        #expect(coordinator.isScanning == false)

        upsertDevices.devices = DeviceDiscoveryCoordinatorFixtures.endToEndDevicesScanB
        coordinator.startScan()
        await waitUntil(timeout: .seconds(30)) { coordinator.isScanning == false }
        #expect(coordinator.isScanning == false)

        let rows = try context.fetch(FetchDescriptor<LocalDevice>())
            .map {
                DeviceDiscoveryCoordinatorFixtures.Row(
                    ipAddress: $0.ipAddress,
                    macAddress: $0.macAddress,
                    hostname: $0.hostname,
                    vendor: $0.vendor,
                    status: $0.status,
                    lastLatency: $0.lastLatency,
                    openPorts: $0.openPorts
                )
            }
            .sorted { $0.ipAddress < $1.ipAddress }

        #expect(rows == DeviceDiscoveryCoordinatorFixtures.expectedRowsAfterEndToEndScans.sorted { $0.ipAddress < $1.ipAddress })
    }

    // MARK: - #279 fallback interface selection (no active NetworkProfile)
    //
    // Not every Mac's primary LAN interface is en0 (observed on the automation node:
    // en0 down, LAN reachable only via en1). `selectFallbackInterface` takes an injectable
    // `networkProvider` specifically so this selection logic is testable without real
    // interface syscalls.

    @Test func selectFallbackInterfacePicksFirstCandidateWithALiveNetwork() {
        let liveNetwork = NetworkUtilities.IPv4Network(
            networkAddress: 0,
            broadcastAddress: 0,
            interfaceAddress: 0,
            netmask: 0
        )
        let selected = DeviceDiscoveryCoordinator.selectFallbackInterface(
            candidates: ["en0", "en1", "en2"],
            networkProvider: { $0 == "en1" ? liveNetwork : nil }
        )
        #expect(selected == "en1")
    }

    @Test func selectFallbackInterfaceReturnsNilWhenNoCandidateHasALiveNetwork() {
        let selected = DeviceDiscoveryCoordinator.selectFallbackInterface(
            candidates: ["en0", "en1"],
            networkProvider: { _ in nil }
        )
        #expect(selected == nil)
    }

    // MARK: - #279 cancellation

    @Test func stopScanDuringFixturePhaseReleasesConnectionBudgetAndStopsScanning() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(),
            pipelineFactory: { _ in
                ScanPipeline(steps: [
                    ScanPipeline.Step(phases: [FixtureSleepingScanPhase()], concurrent: false)
                ])
            },
            portChecker: { _, _, _ in false }
        )

        // `ConnectionBudget.shared` is process-global: earlier suites in the same test
        // host (e.g. live-Bonjour tests killed by their time limit) can leave slots
        // active, so assert relative to the count observed before this scan rather
        // than against zero (#287).
        let activeBefore = await ConnectionBudget.shared.activeCount

        coordinator.startScan()
        // Give the fixture phase a moment to start sleeping and acquire its connection slot.
        try? await Task.sleep(for: .milliseconds(100))
        coordinator.stopScan()

        await waitUntil { coordinator.isScanning == false }
        #expect(coordinator.isScanning == false)

        // ScanEngine's per-phase timeout race resolves (and the phase's task returns)
        // as soon as its cancellation handler fires, which can be before the phase's own
        // `operationTask` — and therefore its `withConnectionSlot` release — has actually
        // unwound. Poll instead of asserting once to avoid racing that unwind.
        await waitUntil(timeout: .seconds(10)) { await ConnectionBudget.shared.activeCount <= activeBefore }
        let activeAfter = await ConnectionBudget.shared.activeCount
        #expect(activeAfter <= activeBefore, "fixture phase's slot must be released: before=\(activeBefore) after=\(activeAfter)")
    }

    private func makeCoordinator(context: ModelContext) -> DeviceDiscoveryCoordinator {
        DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager()
        )
    }
}

// MARK: - Shared test helpers
//
// File-scope (not struct members) so both `DeviceDiscoveryCoordinatorTests` and
// `DeviceDiscoveryEnrichmentTests` below can use them without duplication —
// kept split into two suites only to stay under SwiftLint's `type_body_length`.

@MainActor
private func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
    let schema = Schema([LocalDevice.self])
    let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    return (container, container.mainContext)
}

/// Polls `condition` until it's true or `timeout` elapses — used instead of a fixed
/// sleep so these tests complete as soon as the coordinator's scan task actually
/// finishes, without reaching into its `private` `scanTask`. `condition` may itself
/// `await` actor-isolated state (e.g. `ConnectionBudget.shared.activeCount`); a plain
/// synchronous closure is also accepted since a sync closure trivially satisfies an
/// `async` closure parameter.
@MainActor
private func waitUntil(timeout: Duration = .seconds(10), _ condition: () async -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while await !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(20))
    }
}

/// A `MACVendorLookupService` whose online lookup is intercepted by `MockURLProtocol`
/// and always answers "Not Found" — deterministic, and never reaches macvendors.com,
/// for tests that need `VendorLookupPhase` to run (rather than being omitted from the
/// fixture pipeline entirely) without depending on the network.
private func makeOfflineVendorService() -> MACVendorLookupService {
    MACVendorLookupService(session: MockURLProtocol.makeSession { request in
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            throw URLError(.badURL)
        }
        return (response, Data("Not Found".utf8))
    })
}

@Suite(.serialized)
@MainActor
struct DeviceDiscoveryEnrichmentTests {

    // MARK: - P2 (#297) E1: enrichment applies only to devices seen this scan

    /// A "seen last scan, absent this scan" device must not be re-resolved or re-pinged by
    /// the macOS enrichment phases (E1). Before P2, `resolveDeviceNames`/`measureDeviceLatencies`
    /// queried persisted `LocalDevice` rows filtered only by status/emptiness — reaching
    /// stale rows `markOfflineDevices` hadn't flipped yet. The phases now read only the
    /// `ScanAccumulator`, which by construction holds just this scan's devices, so this test
    /// proves that structurally rather than just asserting on the resulting rows.
    @Test func enrichmentPhasesSkipStaleDevicesNotSeenThisScan() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        // Persisted from an earlier scan; absent from this scan's fixture discovery below.
        // `networkProfileID` defaults to nil (LocalDevice's init default), so the coordinator
        // below is given a profile manager with no ambient host state (E1's "seen last scan"
        // device must match on `networkProfileID == nil` deterministically) rather than the
        // default `NetworkProfileManager()`, which reads the real host's detected network and
        // would give `effectiveProfileID()` a non-nil UUID this stale row never gets — on such
        // a host `fetchDevices(for:)` would silently exclude the stale row from every query
        // below, including `markOfflineDevices`, independent of anything this phase does.
        let stale = LocalDevice(
            ipAddress: "192.0.2.77",
            macAddress: "AA:BB:CC:DD:EE:77",
            hostname: nil
        )
        stale.status = .online
        context.insert(stale)
        try context.save()

        let resolverCalls = CallRecorder()
        let pingerCalls = CallRecorder()
        let vendorService = makeOfflineVendorService()
        let noAmbientDefaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let noAmbientProfileManager = NetworkProfileManager(
            userDefaults: noAmbientDefaults,
            activeProfilesProvider: { [] }
        )

        let seedDevices = FixtureUpsertBox(devices: [
            DiscoveredDevice(
                ipAddress: "192.0.2.78",
                hostname: nil,
                vendor: nil,
                macAddress: "AA:BB:CC:DD:EE:78",
                latency: nil,
                discoveredAt: Date(),
                source: .local
            )
        ])

        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: noAmbientProfileManager,
            pipelineFactory: { _ in
                ScanPipeline(steps: [
                    ScanPipeline.Step(phases: [FixtureUpsertScanPhase(box: seedDevices)], concurrent: false),
                    ScanPipeline.Step(phases: [
                        ShellNameResolutionPhase(resolver: { ip in
                            await resolverCalls.record(ip)
                            return nil
                        }),
                        VendorLookupPhase(service: vendorService),
                        QuickPortScanPhase(checker: { _, _, _ in false }),
                        ShellPingLatencyPhase(pinger: { ip in
                            await pingerCalls.record(ip)
                            return nil
                        }),
                    ], concurrent: true),
                ])
            },
            portChecker: { _, _, _ in false }
        )

        coordinator.startScan()
        await waitUntil(timeout: .seconds(15)) { coordinator.isScanning == false }
        #expect(coordinator.isScanning == false)

        let resolvedIPs = await resolverCalls.calledIPs
        let pingedIPs = await pingerCalls.calledIPs
        #expect(!resolvedIPs.contains("192.0.2.77"), "a stale device must not be re-resolved (E1)")
        #expect(!pingedIPs.contains("192.0.2.77"), "a stale device must not be re-pinged (E1)")
        #expect(resolvedIPs.contains("192.0.2.78"), "this scan's own device should still be resolved")
        #expect(pingedIPs.contains("192.0.2.78"), "this scan's own device should still be pinged")

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        let staleAfter = devices.first { $0.ipAddress == "192.0.2.77" }
        #expect(staleAfter?.status == .offline, "a device absent from this scan must be marked offline")
        #expect(staleAfter?.hostname == nil, "a stale device's hostname must remain untouched")
    }

    // MARK: - P2 (#297) E2: latencyHistory grows by exactly one point per scan

    /// `ICMPLatencyPhase` (discovery step 3) already populates latency by the time the
    /// sparse merge fires at the discovery→enrichment transition. If that merge called
    /// `LocalDevice.updateLatency` (which appends to the sparkline buffer), every device
    /// would get two points per scan instead of one. A test that only compares rows would
    /// pass while this regressed — this asserts on `latencyHistory.count` directly.
    @Test func latencyHistoryGrowsByExactlyOnePerScan() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let vendorService = makeOfflineVendorService()
        let seedDevices = FixtureUpsertBox(devices: [
            DiscoveredDevice(
                ipAddress: "192.0.2.10",
                hostname: "device.local",
                vendor: nil,
                macAddress: "AA:BB:CC:DD:EE:10",
                latency: 12.5,
                discoveredAt: Date(),
                source: .local
            )
        ])

        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(),
            pipelineFactory: { _ in
                ScanPipeline(steps: [
                    ScanPipeline.Step(phases: [FixtureUpsertScanPhase(box: seedDevices)], concurrent: false),
                    ScanPipeline.Step(phases: [
                        ShellNameResolutionPhase(resolver: { _ in nil }),
                        VendorLookupPhase(service: vendorService),
                        QuickPortScanPhase(checker: { _, _, _ in false }),
                        ShellPingLatencyPhase(pinger: { _ in nil }),
                    ], concurrent: true),
                ])
            },
            portChecker: { _, _, _ in false }
        )

        coordinator.startScan()
        await waitUntil(timeout: .seconds(15)) { coordinator.isScanning == false }
        #expect(coordinator.isScanning == false)

        let device = try context.fetch(FetchDescriptor<LocalDevice>()).first { $0.ipAddress == "192.0.2.10" }
        #expect(device?.lastLatency == 12.5)
        #expect(device?.latencyHistory.count == 1, "latencyHistory must grow by exactly one point per scan (E2)")
    }

    // MARK: - P2 (#297): the enrichment step actually writes what each phase finds
    //
    // The tests above prove call-through (E1) and the merge timing (E2), but neither proves
    // any phase's *write* reaches the persisted row: `enrichmentPhasesSkipStaleDevicesNotSeenThisScan`
    // uses stub dependencies that all return nil/false, and `startScanWithFixturePipelineProducesGoldenRowsAcrossTwoScans`
    // opts out of enrichment entirely, so its columns come from the fixture `DiscoveredDevice`s,
    // not from any phase. If `VendorLookupPhase` silently wrote nothing, or `QuickPortScanPhase`
    // dropped `openPorts` on the upsert, or `ShellPingLatencyPhase` passed the wrong
    // `LatencySource`, every existing test would still pass. This test runs `startScan()`
    // through the real `ScanPipelineInputs.standardEnrichmentStep` — the actual four-phase
    // composition `pipelineFactory`'s production default uses — with deterministic non-nil
    // dependencies substituted for the ones that would otherwise shell out or hit the network
    // (`nameResolver`, `portChecker`, `pingRunner` are closures; `macVendorService` is the real
    // `MACVendorLookupService` given a MAC whose OUI resolves from its local table, so the
    // online macvendors.com path is never reached).

    @Test func standardEnrichmentStepWritesAllFourFieldsAndRespectsLatencyRank() async throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let deviceAIP = "192.0.2.30"
        let deviceAMAC = "00:03:93:11:22:33" // known local-OUI prefix (Apple) — no network lookup
        let deviceBIP = "192.0.2.31"
        let deviceBMAC = "AA:BB:CC:DD:EE:31" // not in the local OUI table
        let icmpSeededLatency = 4.2 // seeded at .icmp rank before the enrichment step runs
        let deviceAPingedLatency = 7.5
        let overwriteAttemptLatency = 99.9 // what a rank-ignoring bug would write over deviceB

        let seedDevices = FixtureUpsertBox(devices: [
            DiscoveredDevice(
                ipAddress: deviceAIP, hostname: nil, vendor: nil, macAddress: deviceAMAC,
                latency: nil, discoveredAt: Date(), source: .local
            ),
            DiscoveredDevice(
                ipAddress: deviceBIP, hostname: nil, vendor: nil, macAddress: deviceBMAC,
                latency: nil, discoveredAt: Date(), source: .local
            ),
        ])

        let vendorService = makeOfflineVendorService()
        let pingerCalls = CallRecorder()
        let noAmbientDefaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let noAmbientProfileManager = NetworkProfileManager(
            userDefaults: noAmbientDefaults,
            activeProfilesProvider: { [] }
        )

        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: noAmbientProfileManager,
            pipelineFactory: { _ in
                let inputs = ScanPipelineInputs(
                    bonjourServiceProvider: { [] },
                    bonjourStopProvider: {},
                    nameResolver: { ip in ip == deviceAIP ? "device-a.local" : nil },
                    macVendorService: vendorService,
                    portChecker: { ip, port, _ in ip == deviceAIP && (port == 22 || port == 443) },
                    pingRunner: { ip in
                        await pingerCalls.record(ip)
                        return ip == deviceAIP ? deviceAPingedLatency : overwriteAttemptLatency
                    }
                )
                return ScanPipeline(steps: [
                    ScanPipeline.Step(phases: [FixtureUpsertScanPhase(box: seedDevices)], concurrent: false),
                    // Seeds deviceB's latency at .icmp rank, simulating ICMPLatencyPhase having
                    // already measured it — before the enrichment step's ShellPingLatencyPhase runs.
                    ScanPipeline.Step(phases: [FixtureICMPSeedPhase(ip: deviceBIP, latency: icmpSeededLatency)], concurrent: false),
                    inputs.standardEnrichmentStep,
                ])
            },
            portChecker: { _, _, _ in false }
        )

        coordinator.startScan()
        await waitUntil(timeout: .seconds(15)) { coordinator.isScanning == false }
        #expect(coordinator.isScanning == false)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        let deviceA = devices.first { $0.ipAddress == deviceAIP }
        let deviceB = devices.first { $0.ipAddress == deviceBIP }

        #expect(deviceA?.hostname == "device-a.local", "ShellNameResolutionPhase must write the resolved hostname")
        #expect(deviceA?.vendor == "Apple", "VendorLookupPhase must write the looked-up vendor")
        #expect(deviceA?.openPorts == [22, 443], "QuickPortScanPhase must write the open ports it found")
        #expect(deviceA?.lastLatency == deviceAPingedLatency, "ShellPingLatencyPhase must write latency for a device ICMP never measured")

        #expect(deviceB?.lastLatency == icmpSeededLatency, "ShellPingLatencyPhase must not overwrite a latency already ranked .icmp (ADR-003)")
        let pingedIPs = await pingerCalls.calledIPs
        #expect(!pingedIPs.contains(deviceBIP), "a device whose latency is already ranked .icmp must never reach the shell-ping fallback")
    }
}

/// Records IPs a fixture `resolver`/`pinger` closure was called with, for tests proving a
/// stale device (E1) is never touched. An actor because the four enrichment phases in
/// `ScanPipeline.Step(concurrent: true)` may call these closures concurrently.
private actor CallRecorder {
    private(set) var calledIPs: [String] = []

    func record(_ ip: String) {
        calledIPs.append(ip)
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

/// Test-only `ScanPhase` that sets a device's latency at a specific `LatencySource` rank —
/// used to seed a device as if `ICMPLatencyPhase` had already measured it, so
/// `ShellPingLatencyPhase`'s "never overwrite .icmp" contract (ADR-003) can be exercised
/// deterministically. Must run after the device is already upserted (`setLatency` is a no-op
/// for an IP the accumulator doesn't know about yet).
private struct FixtureICMPSeedPhase: ScanPhase, Sendable {
    let id: ScanPhaseID = "fixtureIcmpSeed"
    let displayName = "Fixture ICMP seed"
    let weight: Double = 1.0
    let ip: String
    let latency: Double

    func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        await onProgress(0.0)
        await accumulator.setLatency(ip: ip, value: latency, source: .icmp)
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
