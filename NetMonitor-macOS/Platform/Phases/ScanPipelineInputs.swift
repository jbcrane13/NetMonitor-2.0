import Foundation
import NetMonitorCore
import NetworkScanKit

/// Carries every dependency `pipelineFactory` needs to build a scan pipeline for a single
/// `startScan()` call.
///
/// Before this (E9), `pipelineFactory` was `(bonjourServiceProvider, bonjourStopProvider) ->
/// ScanPipeline` — it could see only the two Bonjour providers, so it had no way to reach
/// `nameResolver`, `macVendorService` or `portChecker` and therefore could not construct the
/// macOS enrichment phases. This struct widens the factory's input to everything it needs.
struct ScanPipelineInputs: Sendable {
    let bonjourServiceProvider: @Sendable () async -> [BonjourServiceInfo]
    let bonjourStopProvider: @Sendable () async -> Void

    /// Resolves a hostname for an IP still missing one after `ReverseDNSScanPhase`. A
    /// closure — not the concrete `ShellDeviceNameResolver` actor — so a fixture pipeline
    /// can inject a deterministic stub instead of shelling out to `host`/`dig`/`smbutil`.
    let nameResolver: @Sendable (_ ipAddress: String) async -> String?

    /// `MACVendorLookupService` already exposes a test seam (an injectable `URLSession`
    /// via its `init(session:)`), so the concrete actor is itself the injection point.
    let macVendorService: MACVendorLookupService

    /// Checks whether `host:port` is reachable. Same shape as
    /// `DeviceDiscoveryCoordinator`'s `portChecker`, which stays on the coordinator's init.
    let portChecker: @Sendable (_ host: String, _ port: Int, _ timeoutMs: Int32) async -> Bool

    /// Shell-ping fallback (ADR-003 / E3) for devices ICMP didn't cover. Returns the
    /// measured latency, or `nil` if unreachable.
    let pingRunner: @Sendable (_ host: String) async -> Double?

    /// The standard macOS enrichment step run after discovery: shell name resolution
    /// (leftovers after `ReverseDNSScanPhase`), vendor lookup, a quick port scan, and the
    /// shell-ping latency fallback — all four concurrently, matching today's behaviour where
    /// these post-scan passes have no ordering dependency on one another.
    var standardEnrichmentStep: ScanPipeline.Step {
        ScanPipeline.Step(
            phases: [
                ShellNameResolutionPhase(resolver: nameResolver),
                VendorLookupPhase(service: macVendorService),
                QuickPortScanPhase(checker: portChecker),
                ShellPingLatencyPhase(pinger: pingRunner),
            ],
            concurrent: true
        )
    }
}
