import Foundation
import NetMonitorCore
import NetworkScanKit
@testable import NetMonitor_macOS

/// Records IPs a fixture `resolver`/`pinger` closure was called with, for tests proving a
/// stale device (E1) is never touched. An actor because the four enrichment phases in
/// `ScanPipeline.Step(concurrent: true)` may call these closures concurrently.
actor CallRecorder {
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
final class FixtureUpsertBox: @unchecked Sendable {
    var devices: [DiscoveredDevice]
    init(devices: [DiscoveredDevice]) {
        self.devices = devices
    }
}

/// Test-only `ScanPhase` that upserts a fixed set of devices into the accumulator — used
/// to drive `startScan()` deterministically without touching any live network, mirroring
/// what `ScanEngine`'s real ARP/Bonjour/TCP/SSDP phases would produce.
struct FixtureUpsertScanPhase: ScanPhase, Sendable {
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
struct FixtureICMPSeedPhase: ScanPhase, Sendable {
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
struct FixtureSleepingScanPhase: ScanPhase, Sendable {
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
