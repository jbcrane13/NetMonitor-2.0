import Foundation
import NetworkScanKit

extension ScanPhaseID {
    static let shellPingLatency = ScanPhaseID(rawValue: "shellPingLatency")
}

/// ADR-003 fallback-only latency pass (E3): pings only entries `ICMPLatencyPhase` didn't
/// cover, and sends nothing when ICMP already measured every device. Writes with source
/// `.shellPing` — `ScanAccumulator.setLatency` ranks it below `.icmp`, so it can never
/// downgrade a reading ICMP already produced.
struct ShellPingLatencyPhase: ScanPhase, Sendable {
    let id: ScanPhaseID = .shellPingLatency
    let displayName = "Pinging remaining devices…"
    let weight: Double
    let timeout: Duration?

    /// Pings one host and returns the measured latency, or `nil` if unreachable. Injected
    /// so fixture pipelines are deterministic — the production default shells out via
    /// `ShellPingService` (3 probes, matching today's min-of-3 semantics).
    private let pinger: @Sendable (_ host: String) async -> Double?

    /// Matches the retired `measureDeviceLatencies`'s thermal-aware sliding-window base.
    private let maxConcurrentPings: Int

    init(
        pinger: @escaping @Sendable (_ host: String) async -> Double?,
        weight: Double = 0.03,
        maxConcurrentPings: Int = 10,
        timeout: Duration? = .seconds(60)
    ) {
        self.pinger = pinger
        self.weight = weight
        self.maxConcurrentPings = maxConcurrentPings
        self.timeout = timeout
    }

    func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        guard !Task.isCancelled else { return }
        await onProgress(0.0)

        let ips = await accumulator.ipsNeedingLatency(below: .icmp)
        guard !ips.isEmpty else {
            await onProgress(1.0)
            return
        }

        let total = ips.count
        var completed = 0
        let concurrencyLimit = ThermalThrottleMonitor.shared.effectiveLimit(from: maxConcurrentPings)
        let pinger = self.pinger

        await forEachBounded(ips, limit: concurrencyLimit, operation: { ip -> (String, Double?) in
            await (ip, pinger(ip))
        }, onResult: { ip, latency in
            completed += 1
            if let latency {
                await accumulator.setLatency(ip: ip, value: latency, source: .shellPing)
            }
            await onProgress(Double(completed) / Double(max(total, 1)))
        })

        await onProgress(1.0)
    }
}
