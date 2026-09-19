import Foundation

/// Resolves hostnames for discovered devices that are missing one,
/// using reverse DNS (PTR) lookups.
public struct ReverseDNSScanPhase: ScanPhase, Sendable {
    public let id: ScanPhaseID = .reverseDNS
    public let displayName = "Resolving names…"
    public let weight: Double = 0.08

    /// Maximum number of concurrent PTR lookups.
    let maxConcurrentResolves: Int

    public init(maxConcurrentResolves: Int = 8) {
        self.maxConcurrentResolves = maxConcurrentResolves
    }

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        guard !Task.isCancelled else { return }
        await onProgress(0.0)

        let devices = await accumulator.snapshot()
        let devicesNeedingNames = devices.filter { $0.hostname == nil }
        guard !devicesNeedingNames.isEmpty else {
            await onProgress(1.0)
            return
        }

        let nameResolver = DeviceNameResolver()
        let total = devicesNeedingNames.count
        var resolved = 0

        await forEachBounded(devicesNeedingNames, limit: maxConcurrentResolves, operation: { device -> (String, String?) in
            let name = await nameResolver.resolve(ipAddress: device.ipAddress)
            return (device.ipAddress, name)
        }, onResult: { ip, hostname in
            resolved += 1

            if let hostname {
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

            let progress = Double(resolved) / Double(max(total, 1))
            await onProgress(progress)
        })

        await onProgress(1.0)
    }
}
