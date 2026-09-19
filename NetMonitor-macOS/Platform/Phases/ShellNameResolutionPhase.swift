import Foundation
import NetworkScanKit

extension ScanPhaseID {
    static let shellNameResolution = ScanPhaseID(rawValue: "shellNameResolution")
}

/// Resolves hostnames for accumulator entries `ReverseDNSScanPhase` didn't cover.
///
/// Does **not** replace `ReverseDNSScanPhase`: the engine already runs reverse DNS
/// (`getnameinfo`) earlier in the pipeline, and this phase then handles whatever it missed
/// via `host`/`dig`/`smbutil` — "reverse DNS first, shell for the leftovers" is today's
/// behaviour and is preserved exactly (E9).
struct ShellNameResolutionPhase: ScanPhase, Sendable {
    let id: ScanPhaseID = .shellNameResolution
    let displayName = "Resolving remaining names…"
    let weight: Double
    let timeout: Duration?

    /// Resolves one IP to a hostname, or `nil`. Injected so fixture pipelines are
    /// deterministic — the production default shells out via `ShellDeviceNameResolver`.
    private let resolver: @Sendable (_ ipAddress: String) async -> String?

    /// Matches the retired `resolveDeviceNames`'s sliding-window cap.
    private let maxConcurrentResolves: Int

    init(
        resolver: @escaping @Sendable (_ ipAddress: String) async -> String?,
        weight: Double = 0.08,
        maxConcurrentResolves: Int = 10,
        timeout: Duration? = .seconds(60)
    ) {
        self.resolver = resolver
        self.weight = weight
        self.maxConcurrentResolves = maxConcurrentResolves
        self.timeout = timeout
    }

    func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        guard !Task.isCancelled else { return }
        await onProgress(0.0)

        let devices = await accumulator.snapshot()
        let candidates = devices.filter { $0.hostname == nil || $0.hostname?.isEmpty == true }
        guard !candidates.isEmpty else {
            await onProgress(1.0)
            return
        }

        let total = candidates.count
        var resolved = 0
        let resolver = self.resolver

        await forEachBounded(candidates, limit: maxConcurrentResolves, operation: { device -> (String, String?) in
            await (device.ipAddress, resolver(device.ipAddress))
        }, onResult: { ip, hostname in
            resolved += 1
            if let hostname, !hostname.isEmpty {
                await accumulator.upsert(DiscoveredDevice(
                    ipAddress: ip,
                    hostname: hostname,
                    vendor: nil,
                    macAddress: nil,
                    latency: nil,
                    discoveredAt: Date(),
                    source: .local
                ))
            }
            await onProgress(Double(resolved) / Double(max(total, 1)))
        })

        await onProgress(1.0)
    }
}
